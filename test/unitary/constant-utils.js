const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");


const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const NULL_ADDRESS = "0xffffffffffffffffffffffffffffffffffffffff";

const YEAR = BigNumber.from("86400").mul(365);

const ten_to_the_18 = BigNumber.from("1000000000000000000");
const ten_to_the_6 = BigNumber.from("1000000");
const ten_to_the_5 = BigNumber.from("100000");

const ONE = ethers.BigNumber.from("1");
const TWO = ethers.BigNumber.from("2");

const short = [
    "0x4e69636b00000000000000000000000000000000000000000000000000000000",
];

const wrong = [
    "0x4e69636b0000000000000000000000000000000000000000000000000000000f",
    "0x4e69636b0000000000000000000000000000000000000000000000000000000s",
    "0x4e69636b0000000000000000000000000000000000000000000000000000000a",
];

const long = [
    "0x4e69636b00000000000000000000000000000000000000000000000000000000",
    "0x4e69636b00000000000000000000000000000000000000000000000000000001",
    "0x4e69636b00000000000000000000000000000000000000000000000000000002",
    "0x4e69636b00000000000000000000000000000000000000000000000000000003",
    "0x4e69636b00000000000000000000000000000000000000000000000000000004",
    "0x4e69636b00000000000000000000000000000000000000000000000000000005",
    "0x4e69636b00000000000000000000000000000000000000000000000000000006",
    "0x4e69636b00000000000000000000000000000000000000000000000000000007",
    "0x4e69636b00000000000000000000000000000000000000000000000000000008",
    "0x4e69636b00000000000000000000000000000000000000000000000000000009",
    "0x4e69636b00000000000000000000000000000000000000000000000000000010",
    "0x4e69636b00000000000000000000000000000000000000000000000000000011",
    "0x4e69636b00000000000000000000000000000000000000000000000000000021",
    "0x4e69636b00000000000000000000000000000000000000000000000000000031",
    "0x4e69636b00000000000000000000000000000000000000000000000000000041",
    "0x4e69636b00000000000000000000000000000000000000000000000000000051",
    "0x4e69636b00000000000000000000000000000000000000000000000000000061",
    "0x4e69636b00000000000000000000000000000000000000000000000000000071",
    "0x4e69636b00000000000000000000000000000000000000000000000000000081",
    "0x4e69636b00000000000000000000000000000000000000000000000000000091",
    "0x4e69636b00000000000000000000000000000000000000000000000000000101",
    "0x4e69636b00000000000000000000000000000000000000000000000000000201",
    "0x4e69636b00000000000000000000000000000000000000000000000000000301",
    "0x4e69636b00000000000000000000000000000000000000000000000000000401",
    "0x4e69636b00000000000000000000000000000000000000000000000000000501",
    "0x4e69636b00000000000000000000000000000000000000000000000000000601",
    "0x4e69636b00000000000000000000000000000000000000000000000000000701",
    "0x4e69636b00000000000000000000000000000000000000000000000000000801",
    "0x4e69636b00000000000000000000000000000000000000000000000000000901",
    "0x4e69636b00000000000000000000000000000000000000000000000000001001",
    "0x4e69636b00000000000000000000000000000000000000000000000000001101",
    "0x4e69636b00000000000000000000000000000000000000000000000000001201",
    "0x4e69636b00000000000000000000000000000000000000000000000000001301",
    "0x4e69636b00000000000000000000000000000000000000000000000000001401",
    "0x4e69636b00000000000000000000000000000000000000000000000000001501",
    "0x4e69636b00000000000000000000000000000000000000000000000000001601",
    "0x4e69636b00000000000000000000000000000000000000000000000000001701",
    "0x4e69636b00000000000000000000000000000000000000000000000000001801",
    "0x4e69636b00000000000000000000000000000000000000000000000000001901",
    "0x4e69636b00000000000000000000000000000000000000000000000000002001",
];


Object.assign(exports, {
    ZERO_ADDRESS,
    NULL_ADDRESS,
    YEAR,
    ten_to_the_18,
    ten_to_the_6,
    ten_to_the_5,
    ONE,
    TWO,
    short,
    wrong,
    long
})