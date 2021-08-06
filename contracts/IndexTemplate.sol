pragma solidity ^0.6.0;
/**
 * @author kohshiba
 * @title InsureDAO market template contract
 */

import "./libraries/math/SafeMath.sol";
import "./libraries/utils/Address.sol";
import "./libraries/tokens/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IRegistry.sol";
import "./interfaces/IParameters.sol";
import "./interfaces/IPoolTemplate.sol";
import "./interfaces/ICDS.sol";

contract IndexTemplate is IERC20 {
    using Address for address;
    using SafeMath for uint256;

    /**
     * EVENTS
     */

    event Deposit(
        address indexed depositor,
        uint256 amount,
        uint256 mint,
        uint256 balance,
        uint256 underlying
    );
    event Withdraw(address indexed withdrawer, uint256 amount, uint256 retVal);
    event Compensated(address indexed index, uint256 amount);
    event Paused(bool paused);
    event MetadataChanged(string metadata);
    event LeverageSet(uint256 target);
    event AllocationSet(address pool, uint256 allocPoint);
    /**
     * Storage
     */

    /// @notice Market setting
    bool public initialized;
    bool public paused;
    bool public locked;
    uint256 public pendingEnd;
    string public metadata;

    /// @notice EIP-20 token variables
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    /// @notice External contract call addresses
    IParameters public parameters;
    IVault public vault;
    IRegistry public registry;

    /// @notice Market variables for margin account
    uint256 public totalAllocatedCredit;
    struct PoolInfo {
        uint256 allocPoints;
        uint256 indexToken;
        bool exist;
    }
    mapping(address => PoolInfo) public pools;
    uint256 public totalAllocPoint;
    address[] public poolList;
    uint256 public targetLev; //1x = 1e3

    ///@notice user status management
    struct Withdrawal {
        uint256 timestamp;
        uint256 amount;
    }
    mapping(address => Withdrawal) public withdrawalReq;

    /**
     * @notice Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(
            msg.sender == parameters.get_owner(),
            "Ownable: caller is not the owner"
        );
        _;
    }

    /**
     * Initialize interaction
     */

    /**
     * @notice Initialize market
     * This function registers market conditions.
     * references[0] = paramteres
     * references[1] = vault
     */
    function initialize(
        address _owner,
        string calldata _metaData,
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        uint256[] calldata _conditions,
        address[] calldata _references
    ) external returns (bool) {
        require(
            bytes(_metaData).length > 10 &&
                bytes(_name).length > 0 &&
                bytes(_symbol).length > 0 &&
                _decimals > 0 &&
                _owner != address(0) &&
                _references[0] != address(0) &&
                _references[1] != address(0) &&
                _references[2] != address(0),
            "ERROR: INITIALIZATION_BAD_CONDITIONS"
        );

        initialized = true;

        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        parameters = IParameters(_references[0]);
        vault = IVault(_references[1]);
        registry = IRegistry(_references[2]);

        metadata = _metaData;

        return true;
    }

    /**
     * Pool initeractions
     */

    /**
     * @notice A provider supplies collateral to the pool and receives iTokens
     */
    function deposit(uint256 _amount) public returns (uint256 _mintAmount) {
        require(locked == false && paused == false, "ERROR: DEPOSIT_DISABLED");
        require(_amount > 0);

        uint256 _cds = parameters.getPremium2(_amount, msg.sender);
        uint256 _fee = parameters.getFee2(_amount, msg.sender);
        uint256 _add = _amount.sub(_cds).sub(_fee);
        uint256 _supply = totalSupply();
        uint256 _totalLiquidity = totalLiquidity();
        vault.addValue(_add, msg.sender, address(this));
        vault.addValue(
            _cds,
            msg.sender,
            address(registry.getCDS(address(this)))
        );
        vault.addValue(_fee, msg.sender, parameters.get_owner());

        if (_supply > 0 && _totalLiquidity > 0) {
            _mintAmount = _add.mul(_supply).div(_totalLiquidity);
        } else if (_supply > 0 && _totalLiquidity == 0) {
            _mintAmount = _add.div(_supply);
        } else {
            _mintAmount = _add;
        }
        emit Deposit(
            msg.sender,
            _amount,
            _mintAmount,
            balanceOf(msg.sender),
            valueOfUnderlying(msg.sender)
        );
        //mint iToken
        _mint(msg.sender, _mintAmount);
        adjustAlloc();
    }

    /**
     * @notice Provider request withdrawal of collateral
     */
    function requestWithdraw(uint256 _amount) external {
        uint256 _balance = balanceOf(msg.sender);
        require(
            _balance >= _amount && _amount > 0,
            "ERROR: WITHDRAW_REQUEST_BAD_CONDITIONS"
        );
        withdrawalReq[msg.sender].timestamp = now;
        withdrawalReq[msg.sender].amount = _amount;
    }

    /**
     * @notice Provider burns iToken and receives collatral from the pool
     */
    function withdraw(uint256 _amount) external returns (uint256 _retVal) {
        //Calculate underlying value
        _retVal = totalLiquidity().mul(_amount).div(totalSupply());

        require(
            locked == false &&
                withdrawalReq[msg.sender].timestamp.add(
                    parameters.getLockup(msg.sender)
                ) <
                now &&
                withdrawalReq[msg.sender]
                .timestamp
                .add(parameters.getLockup(msg.sender))
                .add(parameters.getWithdrawable(msg.sender)) >
                now &&
                _retVal <= withdrawable() &&
                withdrawalReq[msg.sender].amount >= _amount &&
                _amount > 0,
            "ERROR: WITHDRAWAL_BAD_CONDITIONS"
        );

        //reduce requested amount
        withdrawalReq[msg.sender].amount = withdrawalReq[msg.sender].amount.sub(
            _amount
        );
        //Burn iToken
        _burn(msg.sender, _amount);

        //Check current leverage rate and get updated target total credit allocation
        uint256 _liquidityAfter = totalLiquidity().sub(_retVal);
        uint256 _targetCredit = targetLev.mul(_liquidityAfter).div(1e3); //Allocatable credit
        address[] memory _poolList = new address[](poolList.length); // log which pool has exceeded
        uint256 _allocatable = _targetCredit;
        uint256 _allocatablePoints = totalAllocPoint;
        //Check each pool and if current credit allocation > target & it is impossble to adjust, then withdraw all availablle credit
        for (uint256 i = 0; i < poolList.length; i++) {
            uint256 _target = _targetCredit
            .mul(pools[poolList[i]].allocPoints)
            .div(totalAllocPoint);
            uint256 _current = IPoolTemplate(poolList[i]).allocatedCredit(
                address(this)
            );
            uint256 _available = IPoolTemplate(poolList[i]).availableBalance();
            if (
                _current > _target &&
                _current.sub(_target) > _available &&
                _available != 0
            ) {
                IPoolTemplate(poolList[i]).withdrawCredit(_available);
                totalAllocatedCredit = totalAllocatedCredit.sub(_available);
                _poolList[i] = address(0);
                _allocatable -= _current.sub(_available);
                _allocatablePoints -= pools[poolList[i]].allocPoints;
            } else {
                _poolList[i] = poolList[i];
            }
        }
        //Check pools that was not falling under the previous criteria, then adjust to meet the target credit allocation.
        for (uint256 i = 0; i < _poolList.length; i++) {
            if (_poolList[i] != address(0)) {
                //Target credit allocation for a pool
                uint256 _target = _allocatable
                .mul(pools[poolList[i]].allocPoints)
                .div(_allocatablePoints);
                //get how much has been allocated for a pool
                uint256 _current = IPoolTemplate(poolList[i]).allocatedCredit(
                    address(this)
                );
                uint256 _available = IPoolTemplate(poolList[i])
                .availableBalance();
                if (_current > _target && _available != 0) {
                    //if allocated credit is higher than the target, try to decrease
                    uint256 _decrease = _current.sub(_target);
                    IPoolTemplate(poolList[i]).withdrawCredit(_decrease);
                    totalAllocatedCredit = totalAllocatedCredit.sub(_decrease);
                }
                if (_current < _target) {
                    //Sometimes we need to allocate more
                    uint256 _allocate = _target.sub(_current);
                    IPoolTemplate(poolList[i]).allocateCredit(_allocate);
                    totalAllocatedCredit = totalAllocatedCredit.add(_allocate);
                }
                if (_current == _target) {
                    IPoolTemplate(poolList[i]).allocateCredit(0);
                }
            }
        }

        //Withdraw liquidity
        vault.withdrawValue(_retVal, msg.sender);

        emit Withdraw(msg.sender, _amount, _retVal);
    }

    /**
     * @notice Get how much can a user withdraw from this index
     * Withdrawable is limited to the amount which does not break the balance of credit allocation
     */
    function withdrawable() public view returns (uint256 _retVal) {
        if (totalLiquidity() > 0) {
            uint256 _lowest;
            for (uint256 i = 0; i < poolList.length; i++) {
                if (pools[poolList[i]].allocPoints > 0) {
                    uint256 _utilization = IPoolTemplate(poolList[i])
                    .utilizationRate();
                    if (i == 0) {
                        _lowest = _utilization;
                    }
                    if (_utilization > _lowest) {
                        _lowest = _utilization;
                    }
                }
            }
            if (leverage() > targetLev) {
                _retVal = 0;
            } else if (_lowest == 0) {
                _retVal = totalLiquidity();
            } else {
                _retVal = (1e8 - _lowest)
                .mul(totalLiquidity())
                .div(1e8)
                .mul(1e3)
                .div(leverage())
                .add(_accruedPremiums());
            }
        } else {
            _retVal = 0;
        }
    }

    /**
     * @notice Adjust allocation of credit based on the target leverage rate
     * We adjust credit allocation to meet the following priorities
     * 1) Keep the leverage rate
     * 2) Make credit allocatuion aligned to credit allocaton points
     * we also clear/withdraw accrued premiums in underlying pools to this pool.
     */
    function adjustAlloc() public {
        //Check current leverage rate and get target total credit allocation
        uint256 _targetCredit = targetLev.mul(totalLiquidity()).div(1e3); //Allocatable credit
        address[] memory _poolList = new address[](poolList.length); // log which pool has exceeded
        uint256 _allocatable = _targetCredit;
        uint256 _allocatablePoints = totalAllocPoint;
        //Check each pool and if current credit allocation > target & it is impossble to adjust, then withdraw all availablle credit
        for (uint256 i = 0; i < poolList.length; i++) {
            uint256 _target = _targetCredit
            .mul(pools[poolList[i]].allocPoints)
            .div(totalAllocPoint);
            uint256 _current = IPoolTemplate(poolList[i]).allocatedCredit(
                address(this)
            );
            uint256 _available = IPoolTemplate(poolList[i]).availableBalance();
            if (
                _current > _target &&
                _current.sub(_target) > _available &&
                _available != 0
            ) {
                IPoolTemplate(poolList[i]).withdrawCredit(_available);
                totalAllocatedCredit = totalAllocatedCredit.sub(_available);
                _poolList[i] = address(0);
                _allocatable -= _current.sub(_available);
                _allocatablePoints -= pools[poolList[i]].allocPoints;
            } else {
                _poolList[i] = poolList[i];
            }
        }
        //Check pools that was not falling under the previous criteria, then adjust to meet the target credit allocation.
        for (uint256 i = 0; i < _poolList.length; i++) {
            if (_poolList[i] != address(0)) {
                //Target credit allocation for a pool
                uint256 _target = _allocatable
                .mul(pools[poolList[i]].allocPoints)
                .div(_allocatablePoints);
                //get how much has been allocated for a pool
                uint256 _current = IPoolTemplate(poolList[i]).allocatedCredit(
                    address(this)
                );

                uint256 _available = IPoolTemplate(poolList[i])
                .availableBalance();
                if (_current > _target && _available != 0) {
                    //if allocated credit is higher than the target, try to decrease
                    uint256 _decrease = _current.sub(_target);
                    IPoolTemplate(poolList[i]).withdrawCredit(_decrease);
                    totalAllocatedCredit = totalAllocatedCredit.sub(_decrease);
                }
                if (_current < _target) {
                    //Sometimes we need to allocate more
                    uint256 _allocate = _target.sub(_current);
                    IPoolTemplate(poolList[i]).allocateCredit(_allocate);
                    totalAllocatedCredit = totalAllocatedCredit.add(_allocate);
                }
                if (_current == _target) {
                    IPoolTemplate(poolList[i]).allocateCredit(0);
                }
            }
        }
    }

    /**
     * Insurance interactions
     */

    /**
     * @notice Make a payout if an accident occured in a underlying pool
     * We compensate underlying pools by the following steps
     * 1) Compensate underlying pools from the liquidtiy of this pool
     * 2) If this pool is unable to cover a compesation, compensate from the CDS pool
     */
    function compensate(uint256 _amount) external {
        require(pools[msg.sender].allocPoints > 0);
        if (vault.underlyingValue(address(this)) >= _amount) {
            //When the deposited value without earned premium is enough to cover
            vault.transferValue(_amount, msg.sender);
        } else {
            //When the deposited value without earned premium is *NOT* enough to cover
            //Withdraw credit to cashout the earnings
            for (uint256 i = 0; i < poolList.length; i++) {
                IPoolTemplate(poolList[i]).allocateCredit(0);
            }
            if (totalLiquidity() < _amount) {
                //Insolvency case
                uint256 _shortage = _amount.sub(totalLiquidity());
                ICDS(registry.getCDS(address(this))).compensate(_shortage);
            }

            vault.transferValue(_amount, msg.sender);
        }
        adjustAlloc();
        emit Compensated(msg.sender, _amount);
    }

    /**
     * Reporting interactions
     */

    /**
     * @notice Resume market
     */
    function resume() external {
        require(pendingEnd <= now);
        locked = false;
    }

    /**
     * @notice lock market withdrawal
     */
    function lock(uint256 _pending) external {
        require(pools[msg.sender].allocPoints > 0);
        uint256 _tempEnd = now.add(_pending);
        if (pendingEnd < _tempEnd) {
            pendingEnd = now.add(_pending);
        }
        locked = true;
    }

    /**
     * iToken functions
     */

    /**
     * @notice See `IERC20.totalSupply`.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice See `IERC20.balanceOf`.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice See `IERC20.transfer`.
     */
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @notice See `IERC20.allowance`.
     */
    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @notice See `IERC20.approve`.
     */
    function approve(address spender, uint256 value)
        public
        override
        returns (bool)
    {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice See `IERC20.transferFrom`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender].sub(amount)
        );
        return true;
    }

    /**
     * @notice Atomically increases the allowance granted to `spender` by the caller.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        public
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].add(addedValue)
        );
        return true;
    }

    /**
     * @notice Atomically decreases the allowance granted to `spender` by the caller.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(subtractedValue)
        );
        return true;
    }

    /**
     * @notice Moves tokens `amount` from `sender` to `recipient`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(
            sender != address(0) && recipient != address(0),
            "ERC20: TRANSFER_BAD_CONDITIONS"
        );

        _beforeTokenTransfer(sender, amount);

        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /**
     * @notice Creates `amount` tokens and assigns them to `account`, increasing
     */
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @notice Destoys `amount` tokens from `account`, reducing the
     */
    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _totalSupply = _totalSupply.sub(value);
        _balances[account] = _balances[account].sub(value);
        emit Transfer(account, address(0), value);
    }

    /**
     * @notice Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     */
    function _approve(
        address _owner,
        address _spender,
        uint256 _value
    ) internal {
        require(
            _owner != address(0) && _spender != address(0),
            "ERC20: APPROVE_BAD_CONDITIONS"
        );

        _allowances[_owner][_spender] = _value;
        emit Approval(_owner, _spender, _value);
    }

    /**
     * Utilities
     */

    /**
     * @notice get the current leverage rate 1e3x
     */
    function leverage() public view returns (uint256 _rate) {
        //check current leverage rate
        if (totalLiquidity() > 0) {
            return totalAllocatedCredit.mul(1e3).div(totalLiquidity());
        } else {
            return 0;
        }
    }

    /**
     * @notice total Liquidity of the pool (how much can the pool sell cover)
     */
    function totalLiquidity() public view returns (uint256 _balance) {
        return vault.underlyingValue(address(this)).add(_accruedPremiums());
    }

    /**
     * @notice Get the exchange rate of LP token against underlying asset(scaled by 1e18)
     */
    function rate() external view returns (uint256) {
        if (_totalSupply > 0) {
            return totalLiquidity().mul(1e18).div(_totalSupply);
        } else {
            return 0;
        }
    }

    /**
     * @notice Get the underlying balance of the `owner`
     */
    function valueOfUnderlying(address _owner) public view returns (uint256) {
        uint256 _balance = balanceOf(_owner);
        if (_balance == 0) {
            return 0;
        } else {
            return _balance.mul(totalLiquidity()).div(totalSupply());
        }
    }

    function getAllPools() external view returns (address[] memory) {
        return poolList;
    }

    /**
     * Admin functions
     */

    /**
     * @notice Used for changing settlementFeeRecipient
     */
    function setPaused(bool state) external onlyOwner {
        paused = state;
        emit Paused(state);
    }

    /**
     * @notice Change metadata string
     */
    function changeMetadata(string calldata _metadata) external onlyOwner {
        metadata = _metadata;
        emit MetadataChanged(_metadata);
    }

    /**
     * @notice Change target leverate rate for this index x 1e3
     */
    function setLeverage(uint256 _target) external onlyOwner {
        targetLev = _target;
        emit LeverageSet(_target);
    }

    /**
     * @notice Change allocation point for each pool
     */
    function set(address _pool, uint256 _allocPoint) public onlyOwner {
        if (totalAllocPoint > 0) {
            totalAllocPoint = totalAllocPoint.sub(pools[_pool].allocPoints).add(
                _allocPoint
            );
        } else {
            totalAllocPoint = _allocPoint;
        }

        pools[_pool].allocPoints = _allocPoint;
        if (pools[_pool].exist == false) {
            pools[_pool].exist == true;
            poolList.push(_pool);
        }
        adjustAlloc();
        emit AllocationSet(_pool, _allocPoint);
    }

    /**
     * Internal functions
     */

    /**
     * @notice Internal function to offset deposit time stamp when transfer iToken
     */
    function _beforeTokenTransfer(address _from, uint256 _amount) internal {
        //withdraw request operation
        uint256 _after = balanceOf(_from).sub(_amount);
        if (_after < withdrawalReq[_from].amount) {
            withdrawalReq[_from].amount = _after;
        }
    }

    /**
     * @notice Get the total equivalent value of credit to token
     */
    function _accruedPremiums() internal view returns (uint256 _totalValue) {
        for (uint256 i = 0; i < poolList.length; i++) {
            _totalValue = _totalValue.add(
                IPoolTemplate(poolList[i]).pendingPremium(address(this))
            );
        }
    }
}
