// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.10;

import {IFaucetFactory} from "faucets/IFaucetFactory.sol";
import {ERC20Faucet} from "faucets/ERC20Faucet.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract ZoraActions {
    function createMultipleStreams(
        address zoraFactory,
        address token,
        address strategy,
        uint64 time,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) public returns(uint256[] memory){
        uint256[] memory ids = new uint256[](recipients.length);
        IFaucetFactory streamFactory = IFaucetFactory(zoraFactory);
        (address faucet,) = streamFactory.faucetForToken(token);
        // front-running?  never heard of it
        ERC20(token).approve(faucet, 100 ether);
        for (uint256 i = 0; i < recipients.length; i++) {
            ids[i]=ERC20Faucet(faucet).mint(recipients[i], amounts[i], time, strategy, false);
        }
        return ids;
    }
}
