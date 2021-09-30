pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract Registry {
    using SafeMath for uint256;
    using Address for address;

    event CommitNewAdmin(uint256 deadline, address future_admin);
    event NewAdmin(address admin);
    event ExistenceSet(
        address indexed target,
        uint256 indexed typeId,
        bytes32 indexed hashId
    );
    event NewMarketRegistered(address market);
    event FactorySet(address factory);
    event CDSSet(address target, address cds);

    address public factory;
    address public owner;
    address public future_owner;
    uint256 public transfer_ownership_deadline;
    uint256 public constant ADMIN_ACTIONS_DELAY = 3 * 86400;

    mapping(address => address) cds; //index => cds
    mapping(address => bool) markets;
    mapping(bytes32 => bool) existence;
    address[] allMarkets;

    /**
     * @notice Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Restricted: caller is not allowed to operate"
        );
        _;
    }

    constructor() public {
        owner = msg.sender;
    }

    function setFactory(address _factory) external {
        require(msg.sender == owner);
        require(_factory != address(0), "dev: zero address");
        factory = _factory;
        emit FactorySet(_factory);
    }

    function supportMarket(address _market) external {
        require(!markets[_market]);
        require(msg.sender == factory || msg.sender == owner);
        require(_market != address(0), "dev: zero address");
        allMarkets.push(_market);
        markets[_market] = true;
        emit NewMarketRegistered(_market);
    }

    function setExistence(address _target, uint256 _typeId) external {
        require(msg.sender == factory || msg.sender == owner);
        bytes32 _hashId = keccak256(abi.encodePacked(_target, _typeId));
        existence[_hashId] = true;
        emit ExistenceSet(_target, _typeId, _hashId);
    }

    function setCDS(address _address, address _cds) external onlyOwner {
        require(_cds != address(0), "dev: zero address");
        cds[_address] = _cds;
        emit CDSSet(_address, _cds);
    }

    function getCDS(address _address) external view returns (address) {
        if (cds[_address] == address(0)) {
            return cds[address(0)];
        } else {
            return cds[_address];
        }
    }

    function confirmExistence(address _target, uint256 _typeId)
        external
        view
        returns (bool)
    {
        return existence[keccak256(abi.encodePacked(_target, _typeId))];
    }

    function isListed(address _market) external view returns (bool) {
        return markets[_market];
    }

    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }

    //----- ownership -----//
    function commit_transfer_ownership(address _owner) external onlyOwner {
        require(transfer_ownership_deadline == 0, "dev: active transfer");
        require(_owner != address(0), "dev: address zero");

        uint256 _deadline = block.timestamp.add(ADMIN_ACTIONS_DELAY);
        transfer_ownership_deadline = _deadline;
        future_owner = _owner;

        emit CommitNewAdmin(_deadline, _owner);
    }

    function apply_transfer_ownership() external onlyOwner {
        require(
            block.timestamp >= transfer_ownership_deadline,
            "dev: insufficient time"
        );
        require(transfer_ownership_deadline != 0, "dev: no active transfer");

        transfer_ownership_deadline = 0;
        address _owner = future_owner;

        owner = _owner;

        emit NewAdmin(owner);
    }
}
