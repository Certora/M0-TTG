// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {SPOGGovernorBase, ISPOGVotes, Governor, GovernorBase} from "src/core/governance/SPOGGovernorBase.sol";

/// @title SPOG Governor Contract
/// @notice This contract is used to govern the SPOG protocol. It is a modified version of the Governor contract from OpenZeppelin.
contract SPOGGovernor is SPOGGovernorBase {
    // @note minimum voting delay in blocks
    uint256 public constant MINIMUM_VOTING_DELAY = 1;

    ISPOGVotes public immutable votingToken;

    uint256 private _votingPeriod;
    uint256 private _votingPeriodChangedBlockNumber;
    uint256 private _votingPeriodChangedEpoch;
    // @note voting with no delay is required for certain proposals
    bool private _emergencyVotingIsOn;

    // private mappings
    mapping(uint256 => ProposalVote) private _proposalVotes;

    // public mappings
    mapping(uint256 => bool) public emergencyProposals;
    // epoch => proposalCount
    mapping(uint256 => uint256) public epochProposalsCount;
    // address => epoch => number of proposals voted on
    mapping(address => mapping(uint256 => uint256)) public accountEpochNumProposalsVotedOn;
    // epoch => cumulative epoch vote weight casted
    mapping(uint256 => uint256) public epochSumOfVoteWeight;

    constructor(
        ISPOGVotes votingTokenContract,
        uint256 quorumNumeratorValue,
        uint256 votingPeriod_,
        string memory name_
    ) SPOGGovernorBase(votingTokenContract, quorumNumeratorValue, name_) {
        votingToken = votingTokenContract;
        _votingPeriod = votingPeriod_;
        _votingPeriodChangedBlockNumber = block.number;
    }

    /// @inheritdoc SPOGGovernorBase
    function initSPOGAddress(address _spogAddress) external override {
        if (spogAddress != address(0)) {
            revert SPOGAddressAlreadySet(spogAddress);
        }

        votingToken.initSPOGAddress(_spogAddress);
        spogAddress = _spogAddress;
    }

    /// @dev get current epoch number - 1, 2, 3, .. etc
    function currentEpoch() public view override returns (uint256) {
        uint256 blocksSinceVotingPeriodChange = block.number - _votingPeriodChangedBlockNumber;

        return _votingPeriodChangedEpoch + blocksSinceVotingPeriodChange / _votingPeriod;
    }

    /// @dev get `block.number` of the start of the next epoch
    function startOfNextEpoch() public view override returns (uint256) {
        uint256 nextEpoch = currentEpoch() + 1;

        return startOfEpoch(nextEpoch);
    }

    /// @dev get `block.number` of the start of the given epoch
    /// we can correctly calculate start of epochs only for current and future epochs
    /// it happens because epoch voting time can be changed more that once
    function startOfEpoch(uint256 epoch) public view override returns (uint256) {
        if (epoch < currentEpoch()) revert EpochInThePast(epoch, currentEpoch());
        uint256 epochsSinceVotingPeriodChange = epoch - _votingPeriodChangedEpoch;

        return _votingPeriodChangedBlockNumber + epochsSinceVotingPeriodChange * _votingPeriod;
    }

    /// @dev Allows batch voting
    /// @notice Uses same params as castVote, but in arrays.
    /// @param proposalIds an array of proposalIds
    /// @param support an array of vote values for each proposal
    function castVotes(uint256[] calldata proposalIds, uint8[] calldata support)
        public
        override
        returns (uint256[] memory)
    {
        if (proposalIds.length != support.length) {
            revert ArrayLengthsMismatch();
        }

        uint256[] memory results = new uint256[](proposalIds.length);
        for (uint256 i; i < proposalIds.length;) {
            results[i] = castVote(proposalIds[i], support[i]);
            unchecked {
                ++i;
            }
        }
        return results;
    }

    /// @dev Allows batch voting
    /// @notice Uses same params as castVote, but in arrays.
    /// @param proposalIds an array of proposalIds
    /// @param support an array of vote values for each proposal
    /// @param v an array of v values for each proposal signature
    /// @param r an array of r values for each proposal signature
    /// @param s an array of s values for each proposal signature
    function castVotesBySig(
        uint256[] calldata proposalIds,
        uint8[] calldata support,
        uint8[] calldata v,
        bytes32[] calldata r,
        bytes32[] calldata s
    ) public virtual returns (uint256[] memory) {
        if (
            proposalIds.length != support.length || proposalIds.length != v.length || proposalIds.length != r.length
                || proposalIds.length != s.length
        ) {
            revert ArrayLengthsMismatch();
        }

        uint256[] memory results = new uint256[](proposalIds.length);
        for (uint256 i; i < proposalIds.length;) {
            results[i] = castVoteBySig(proposalIds[i], support[i], v[i], r[i], s[i]);
            unchecked {
                ++i;
            }
        }
        return results;
    }

    /// @dev Allows provide EIP-712 digest for vote by sig
    /// @param proposalId the proposal id
    /// @param support yes or no
    function hashVote(uint256 proposalId, uint8 support) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support)));
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Update voting time only by SPOG
    /// @param newVotingTime New voting time
    function updateVotingTime(uint256 newVotingTime) external override onlySPOG {
        emit VotingPeriodUpdated(_votingPeriod, newVotingTime);

        _votingPeriod = newVotingTime;
        _votingPeriodChangedBlockNumber = block.number;
        _votingPeriodChangedEpoch = currentEpoch();
    }

    function registerEmergencyProposal(uint256 proposalId) external override onlySPOG {
        emergencyProposals[proposalId] = true;
    }

    function turnOnEmergencyVoting() external override onlySPOG {
        _emergencyVotingIsOn = true;
    }

    function turnOffEmergencyVoting() external override onlySPOG {
        _emergencyVotingIsOn = false;
    }

    /*//////////////////////////////////////////////////////////////
                            OVERRIDE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, GovernorBase) onlySPOG returns (uint256) {
        // update epochProposalsCount. Proposals are voted on in the next epoch
        epochProposalsCount[currentEpoch() + 1]++;

        return super.propose(targets, values, calldatas, description);
    }

    /// @notice override to check that caller is SPOG
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override onlySPOG {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @notice override to count user activity in epochs
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        override
        returns (uint256)
    {
        uint256 weight = super._castVote(proposalId, account, support, reason, params);

        _updateAccountEpochVotes(weight);

        return weight;
    }

    /// @dev update number of proposals account voted for and cumulative vote weight casted in epoch
    function _updateAccountEpochVotes(uint256 weight) private {
        uint256 epoch = currentEpoch();

        // update number of proposals account voted for in current epoch
        accountEpochNumProposalsVotedOn[msg.sender][epoch]++;

        // update cumulative vote weight for epoch if user voted in all proposals
        if (accountEpochNumProposalsVotedOn[msg.sender][epoch] == epochProposalsCount[epoch]) {
            epochSumOfVoteWeight[epoch] += weight;
        }
    }

    /**
     * @dev Overridden version of the {Governor-state} function with added support for emergency proposals.
     */
    function state(uint256 proposalId) public view override(Governor, GovernorBase) returns (ProposalState) {
        ProposalState status = super.state(proposalId);

        // If emergency proposal is `Active` and quorum is reached, change status to `Succeeded` even if deadline is not passed yet.
        // Use only `_quorumReached` for this check, `_voteSucceeded` is not needed as it is the same.
        if (emergencyProposals[proposalId] && status == ProposalState.Active && _quorumReached(proposalId)) {
            return ProposalState.Succeeded;
        }

        return status;
    }

    function votingDelay() public view override returns (uint256) {
        return _emergencyVotingIsOn ? MINIMUM_VOTING_DELAY : startOfNextEpoch() - block.number;
    }

    function votingPeriod() public view override returns (uint256) {
        return _votingPeriod;
    }

    /*//////////////////////////////////////////////////////////////
                            COUNTING MODULE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev See {GovernorBase-COUNTING_MODE}.
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure override returns (string memory) {
        return "support=alpha&quorum=alpha";
    }

    /// @dev See {GovernorBase-hasVoted}.
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
    }

    /// @dev Accessor to the internal vote counts.
    function proposalVotes(uint256 proposalId) public view override returns (uint256 noVotes, uint256 yesVotes) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        return (proposalVote.noVotes, proposalVote.yesVotes);
    }

    /// @dev See {Governor-_quorumReached}.
    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        uint256 proposalQuorum = quorum(proposalSnapshot(proposalId));
        // if token has 0 supply, make sure that quorum was not reached
        // @dev short-circuiting the rare usecase of 0 supply check to save gas
        return proposalQuorum <= proposalVote.yesVotes && proposalQuorum > 0;
    }

    /// @dev See {Governor-_voteSucceeded}.
    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        return _quorumReached(proposalId);
    }

    /// @dev See {Governor-_countVote}.
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 votes, bytes memory)
        internal
        override
    {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        if (proposalVote.hasVoted[account]) {
            revert AlreadyVoted(proposalId, account);
        }
        proposalVote.hasVoted[account] = true;

        if (support == uint8(VoteType.No)) {
            proposalVote.noVotes += votes;
        } else {
            proposalVote.yesVotes += votes;
        }
    }

    fallback() external {
        revert("SPOGGovernor: non-existent function");
    }
}