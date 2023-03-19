// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "test/shared/SPOG_Base.t.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/Governor.sol";

contract SPOG_RemoveList is SPOG_Base {
    function test_Revert_RemoveListWhenNotCallingFromGovernance() public {
        addNewListToSpog();
        address listToRemove = address(list);

        vm.expectRevert("SPOG: Only GovSPOGVote");
        spog.removeList(IList(listToRemove));
    }

    function test_Revert_WhenRemoveList_ByGovSPOGValueHolders() external {
        addNewListToSpog();

        address listToRemove = address(list);

        // create proposal to remove list
        address[] memory targets = new address[](1);
        targets[0] = address(spog);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "removeList(address)",
            listToRemove
        );
        string memory description = "remove list";

        (
            bytes32 hashedDescription,
            uint256 proposalId
        ) = getProposalIdAndHashedDescription(
                govSPOGValue,
                targets,
                values,
                calldatas,
                description
            );

        // update start of next voting period
        govSPOGValue.updateStartOfNextVotingPeriod();

        // vote on proposal
        deployScript.cash().approve(address(spog), deployScript.tax());
        spog.propose(
            IGovSPOG(address(govSPOGValue)),
            targets,
            values,
            calldatas,
            description
        );

        // fast forward to an active voting period
        vm.roll(block.number + govSPOGValue.votingDelay() + 1);

        // cast vote on proposal
        uint8 yesVote = uint8(VoteType.Yes);
        govSPOGValue.castVote(proposalId, yesVote);

        vm.roll(block.number + deployScript.voteTime() + 1);

        // proposal execution is not allowed by govSPOGValue holders
        vm.expectRevert("SPOG: Only GovSPOGVote");
        govSPOGValue.execute(targets, values, calldatas, hashedDescription);

        assertTrue(
            spog.isListInMasterList(listToRemove),
            "List must still be in SPOG"
        );
    }

    function test_SPOGProposalToRemoveList() public {
        addNewListToSpog();

        address listToRemove = address(list);

        // create proposal to remove list
        address[] memory targets = new address[](1);
        targets[0] = address(spog);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "removeList(address)",
            listToRemove
        );
        string memory description = "remove list";

        (
            bytes32 hashedDescription,
            uint256 proposalId
        ) = getProposalIdAndHashedDescription(
                govSPOGVote,
                targets,
                values,
                calldatas,
                description
            );

        // vote on proposal
        deployScript.cash().approve(address(spog), deployScript.tax());
        spog.propose(
            IGovSPOG(address(govSPOGVote)),
            targets,
            values,
            calldatas,
            description
        );

        // assert that spog has cash balance
        assertTrue(
            deployScript.cash().balanceOf(address(spog)) ==
                deployScript.tax() * 2,
            "Balance of SPOG should be 2x tax, one from adding the list and one from the current proposal"
        );

        // check proposal is pending. Note voting is not active until voteDelay is reached
        assertTrue(
            govSPOGVote.state(proposalId) == IGovernor.ProposalState.Pending,
            "Proposal is not in an pending state"
        );

        // fast forward to an active voting period
        vm.roll(block.number + govSPOGVote.votingDelay() + 1);

        // proposal should be active now
        assertTrue(
            govSPOGVote.state(proposalId) == IGovernor.ProposalState.Active,
            "Not in active state"
        );

        // cast vote on proposal
        uint8 yesVote = uint8(VoteType.Yes);
        govSPOGVote.castVote(proposalId, yesVote);
        // fast forward to end of voting period
        vm.roll(block.number + deployScript.voteTime() + 1);

        // check proposal is succeeded
        assertTrue(
            govSPOGVote.state(proposalId) == IGovernor.ProposalState.Succeeded,
            "Not in succeeded state"
        );

        // execute proposal
        govSPOGVote.execute(targets, values, calldatas, hashedDescription);

        // check proposal is executed
        assertTrue(
            govSPOGVote.state(proposalId) == IGovernor.ProposalState.Executed,
            "Proposal not executed"
        );

        // assert that list was removed
        assertTrue(
            !spog.isListInMasterList(listToRemove),
            "List was not removed"
        );
    }
}
