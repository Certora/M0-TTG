// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "test/shared/SPOG_Base.t.sol";

contract MockContract is ERC165CheckerSPOG {}

contract TestERC165CheckerSPOG is SPOG_Base {
    function test_checkSpogInterface() public {
        MockContract checker = new MockContract();

        vm.expectRevert();
        checker.checkSPOGInterface(address(0));

        checker.checkSPOGInterface(address(spog));
    }
}
