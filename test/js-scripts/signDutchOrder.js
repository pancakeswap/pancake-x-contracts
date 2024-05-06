const {ethers} = require("ethers");

const abiCoder = new ethers.AbiCoder;

const swapperPrivateKey = process.argv[2];
const infoParams = process.argv[3].split(",");
const decayStartTime = process.argv[4];
const decayEndTime = process.argv[5];
const inputParams = process.argv[6].split(",");
const outputParams = process.argv[7].split(",");
const permit2Address = process.argv[8];
const reactorAddress = process.argv[9];

const dutchOrderType = {
    PermitWitnessTransferFrom: [
        {name: "permitted", type: "TokenPermissions"},
        {name: "spender", type: "address"},
        {name: "nonce", type: "uint256"},
        {name: "deadline", type: "uint256"},
        {name: "witness", type: "DutchOrder"},
    ],
    DutchOrder: [
        {name: "info", type: "OrderInfo"},
        {type: "uint256", name: "decayStartTime"},
        {type: "uint256", name: "decayEndTime"},
        {type: "address", name: "inputToken"},
        {type: "uint256", name: "inputStartAmount"},
        {type: "uint256", name: "inputEndAmount"},
        {type: "DutchOutput[]", name: "outputs"},
    ],
    DutchOutput: [
        {type: "address", name: "token"},
        {type: "uint256", name: "startAmount"},
        {type: "uint256", name: "endAmount"},
        {type: "address", name: "recipient"},
    ],
    OrderInfo: [
        {type: "address", name: "reactor"},
        {type: "address", name: "swapper"},
        {type: "uint256", name: "nonce"},
        {type: "uint256", name: "deadline"},
        {type: "address", name: "additionalValidationContract"},
        {type: "bytes", name: "additionalValidationData"},
    ],
    TokenPermissions: [
        {type: "address", name: "token"},
        {type: "uint256", name: "amount"},
    ]
}

const swapper = new ethers.Wallet(swapperPrivateKey);
const dutchOrder = {
    info: {
        reactor: infoParams[0],
        swapper: infoParams[1],
        nonce: infoParams[2],
        deadline: infoParams[3],
        additionalValidationContract: infoParams[4],
        additionalValidationData: infoParams[5]
    },
    decayStartTime,
    decayEndTime,
    inputToken: inputParams[0],
    inputStartAmount: inputParams[1],
    inputEndAmount: inputParams[2],
    outputs: [{
        token: outputParams[0],
        startAmount: outputParams[1],
        endAmount: outputParams[2],
        recipient: outputParams[3]
    }]
};

const encodeOrder = abiCoder.encode(
    [
        {
            name: "DutchOrder",
            type: "tuple",
            components: [
                {
                    name: "OrderInfo",
                    type: "tuple",
                    components: [
                        {name: "reactor", type: "address"},
                        {name: "swapper", type: "address"},
                        {name: "nonce", type: "uint256"},
                        {name: "deadline", type: "uint256"},
                        {name: "additionalValidationContract", type: "address"},
                        {name: "additionalValidationData", type: "bytes"},
                    ]
                },
                "uint256",
                "uint256",
                "address",
                "uint256",
                "uint256",
                {
                    name: "DutchOutput",
                    type: "tuple[]",
                    components: [
                        ...dutchOrderType.DutchOutput
                    ]
                },
            ]
        }
    ], [[dutchOrder.info, dutchOrder.decayStartTime, dutchOrder.decayEndTime, dutchOrder.inputToken,dutchOrder.inputStartAmount, dutchOrder.inputEndAmount,dutchOrder.outputs]]
);

swapper.signTypedData({
    name: "Permit2",
    chainId: 31337,
    verifyingContract: permit2Address
}, dutchOrderType, {
    permitted: {
        token: dutchOrder.inputToken,
        amount: dutchOrder.inputStartAmount
    },
    spender: reactorAddress,
    nonce: dutchOrder.info.nonce,
    deadline: dutchOrder.info.deadline,
    witness: {
        ...dutchOrder
    }
}).then((result) => {
    process.stdout.write(abiCoder.encode(["bytes","bytes"],[encodeOrder,result]));
});