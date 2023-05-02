// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {ISPOG} from "src/interfaces/ISPOG.sol";
import {SPOGGovernorFactory} from "src/factories/SPOGGovernorFactory.sol";
import {VoteToken} from "src/tokens/VoteToken.sol";
import {ValueToken} from "src/tokens/ValueToken.sol";

import "test/shared/SPOG_Base.t.sol";
import {ERC20GodMode} from "test/mock/ERC20GodMode.sol";

contract SPOG_reset is SPOG_Base {
    uint8 internal yesVote;
    SPOGGovernorFactory internal governorFactory;

    event NewValueQuorumProposal(uint256 indexed proposalId);
    event SPOGResetExecuted(address indexed newVoteToken, address indexed newVoteGovernor);

    function setUp() public override {
        super.setUp();

        yesVote = 1;
        governorFactory = new SPOGGovernorFactory();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function createNewVoteGovernor(address valueToken) private returns (address) {
        // deploy vote governor from factory
        VoteToken newVoteToken = new VoteToken("new SPOGVote", "vote", valueToken);
        // mint new vote tokens to address(this) and self-delegate
        newVoteToken.mint(address(this), 100e18);
        newVoteToken.delegate(address(this));

        uint256 voteGovernorSalt = deployScript.createSalt("new VoteGovernor");
        uint256 time = 15; // in blocks
        uint256 voteQuorum = 5;
        SPOGGovernor newVoteGovernor =
            governorFactory.deploy(newVoteToken, voteQuorum, time, "new VoteGovernor", voteGovernorSalt);

        IAccessControl(address(newVoteToken)).grantRole(newVoteToken.MINTER_ROLE(), address(newVoteGovernor));
        return address(newVoteGovernor);
    }

    function proposeGovernanceReset(string memory proposalDescription, address valueToken)
        private
        returns (uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
    {
        vm.roll(deployScript.time() * 2);

        address[] memory targets = new address[](1);
        targets[0] = address(spog);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        address newVoteGovernor = createNewVoteGovernor(valueToken);
        bytes memory callData = abi.encodeWithSignature("reset(address)", newVoteGovernor);
        string memory description = proposalDescription;
        calldatas[0] = callData;

        bytes32 hashedDescription = keccak256(abi.encodePacked(description));
        uint256 proposalId = valueGovernor.hashProposal(targets, values, calldatas, hashedDescription);

        // create proposal
        deployScript.cash().approve(address(spog), 12 * deployScript.tax());

        // Check the event is emitted
        expectEmit();
        emit NewValueQuorumProposal(proposalId);

        uint256 spogProposalId = spog.propose(callData, description);

        // Make sure the proposal is immediately (+1 block) votable
        assertEq(valueGovernor.proposalSnapshot(proposalId), block.number + 1);

        assertTrue(spogProposalId == proposalId, "spog proposal id does not match value governor proposal id");

        return (proposalId, targets, values, calldatas, hashedDescription);
    }

    function executeValidProposal() private {
        SPOGGovernor voteGovernor = SPOGGovernor(payable(address(spog.voteGovernor())));
        address[] memory targets = new address[](1);
        targets[0] = address(spog);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("addNewList(address)", list);
        string memory description = "Add new list";

        (bytes32 hashedDescription, uint256 proposalId) =
            getProposalIdAndHashedDescription(voteGovernor, targets, values, calldatas, description);

        // vote on proposal
        deployScript.cash().approve(address(spog), deployScript.tax());
        spog.propose(targets, values, calldatas, description);

        // fast forward to an active voting period
        vm.roll(block.number + voteGovernor.votingDelay() + 1);

        // cast vote on proposal
        voteGovernor.castVote(proposalId, yesVote);
        // fast forward to end of voting period
        vm.roll(block.number + voteGovernor.votingPeriod() + 1);

        // execute proposal
        spog.execute(targets, values, calldatas, hashedDescription);
    }

    function test_Revert_Reset_WhenNotCalledFromValueGovernance() public {
        vm.expectRevert("SPOG: Only value governor");
        spog.reset(ISPOGGovernor(address(voteGovernor)));
    }

    function test_Revert_Reset_WhenValueAndVoteTokensMistmatch() public {
        vm.startPrank(address(valueGovernor));
        ValueToken newValueToken = new ValueToken("new Value token", "value");
        address governor = createNewVoteGovernor(address(newValueToken));
        vm.expectRevert(ISPOG.ValueTokenMistmatch.selector);
        spog.reset(ISPOGGovernor(governor));
    }

    function test_Reset_Success() public {
        (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 hashedDescription
        ) = proposeGovernanceReset("Propose reset of vote governance", address(spogValue));

        assertTrue(valueGovernor.state(proposalId) == IGovernor.ProposalState.Pending, "Not in pending state");

        // fast forward to an active voting period
        vm.roll(block.number + 2);
        assertTrue(valueGovernor.state(proposalId) == IGovernor.ProposalState.Active, "Not in active state");

        // value holders vote on proposal
        valueGovernor.castVote(proposalId, yesVote);

        // fast forward to end of voting period
        vm.roll(block.number + deployScript.time() + 1);

        address voteGovernorBeforeFork = address(spog.voteGovernor());

        vm.expectEmit(false, false, false, false);
        address anyAddress = address(0);
        emit SPOGResetExecuted(anyAddress, anyAddress);
        spog.execute(targets, values, calldatas, hashedDescription);

        assertFalse(address(spog.voteGovernor()) == voteGovernorBeforeFork, "Vote governor was not reset");
        assertEq(spog.voteGovernor().quorumNumerator(), 5, "Vote governor quorum was not set correctly");
        assertEq(spog.voteGovernor().votingPeriod(), 15, "Vote governor voting delay was not set correctly");

        // Make sure governance is functional
        executeValidProposal();
    }

    function test_Reset_VoteAndValueTokensAreNotInflated() public {
        uint256 voteTokenInitialBalanceForVault = spogVote.balanceOf(address(vault));
        uint256 valueTokenInitialBalanceForVault = spogValue.balanceOf(address(vault));
        uint256 voteTotalBalance = spogVote.totalSupply();
        uint256 valueTotalBalance = spogValue.totalSupply();

        proposeGovernanceReset("Propose reset of vote governance", address(spogValue));

        uint256 voteTokenBalanceAfterProposal = spogVote.balanceOf(address(vault));
        uint256 valueTokenBalanceAfterProposal = spogValue.balanceOf(address(vault));
        uint256 voteTotalBalanceAfterProposal = spogVote.totalSupply();
        uint256 valueTotalBalanceAfterProposal = spogValue.totalSupply();
        assertEq(
            voteTokenInitialBalanceForVault,
            voteTokenBalanceAfterProposal,
            "vault should have the same balance of vote tokens after reset proposal"
        );
        assertEq(
            valueTokenInitialBalanceForVault,
            valueTokenBalanceAfterProposal,
            "vault should have the same balance of value tokens after reset proposal"
        );
        assertEq(
            voteTotalBalance,
            voteTotalBalanceAfterProposal,
            "total supply of vote tokens should not change after reset proposal"
        );
        assertEq(
            valueTotalBalance,
            valueTotalBalanceAfterProposal,
            "total supply of value tokens should not change after reset proposal"
        );
    }
}