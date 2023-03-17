// SPDX-License-Identifier: GLP-3.0
pragma solidity 0.8.17;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface IVotesForSPOG is IVotes {
    function initSPOGAddress(address _spogAddress) external;
}