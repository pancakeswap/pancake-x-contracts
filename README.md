## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Deployment Addresses

| Chain | ExclusiveDutchOrderReactor | Permit2 |
|-------|---------------------------|---------|
| BNB Chain | `0xDB9D365b50E62fce747A90515D2bd1254A16EbB9` | `0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768` |
| Arbitrum | `0x35db01D1425685789dCc9228d47C7A5C049388d8` | `0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768` |
| Ethereum | `0x35db01D1425685789dCc9228d47C7A5C049388d8` | `0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768` |
| Base | `0x6b9906d7106e5890852Bf98eF13ba5D8761712b9` | `0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768` |

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
