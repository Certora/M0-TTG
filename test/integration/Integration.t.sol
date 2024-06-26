// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { IEmergencyGovernor } from "../../src/interfaces/IEmergencyGovernor.sol";
import { IEmergencyGovernorDeployer } from "../../src/interfaces/IEmergencyGovernorDeployer.sol";
import { IPowerToken } from "../../src/interfaces/IPowerToken.sol";
import { IPowerTokenDeployer } from "../../src/interfaces/IPowerTokenDeployer.sol";
import { IRegistrar } from "../../src/interfaces/IRegistrar.sol";
import { IGovernor } from "../../src/abstract/interfaces/IGovernor.sol";
import { IStandardGovernor } from "../../src/interfaces/IStandardGovernor.sol";
import { IStandardGovernorDeployer } from "../../src/interfaces/IStandardGovernorDeployer.sol";
import { IZeroGovernor } from "../../src/interfaces/IZeroGovernor.sol";
import { IZeroToken } from "../../src/interfaces/IZeroToken.sol";

import { DeployBase } from "../../script/DeployBase.sol";

import { PureEpochs } from "../../src/libs/PureEpochs.sol";

import { ERC20ExtendedHarness } from "../utils/ERC20ExtendedHarness.sol";
import { TestUtils } from "../utils/TestUtils.sol";

contract IntegrationTests is TestUtils {
    IRegistrar internal _registrar;

    ERC20ExtendedHarness internal _cashToken1 = new ERC20ExtendedHarness("Cash Token 1", "CASH1", 6);
    ERC20ExtendedHarness internal _cashToken2 = new ERC20ExtendedHarness("Cash Token 1", "CASH2", 6);

    address[] internal _allowedCashTokens = [address(_cashToken1), address(_cashToken2)];

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");
    address internal _eve = makeAddr("eve");
    address internal _frank = makeAddr("frank");

    address[][2] internal _initialAccounts = [[_alice, _bob, _carol], [_dave, _eve, _frank]];

    uint256[][2] internal _initialBalances = [[uint256(55), 25, 20], [uint256(60_000_000), 30_000_000, 10_000_000]];

    uint256 internal _standardProposalFee = 1_000;

    DeployBase internal _deploy;

    function setUp() external {
        _deploy = new DeployBase();

        // NOTE: Using `DeployBase` as a contract instead of a script, means that the deployer is `_deploy` itself.
        address registrar_ = _deploy.deploy(
            address(_deploy),
            1,
            _initialAccounts,
            _initialBalances,
            _standardProposalFee,
            _allowedCashTokens
        );

        _registrar = IRegistrar(registrar_);
    }

    function test_initialState() external {
        IPowerToken powerToken_ = IPowerToken(_registrar.powerToken());
        uint256 initialPowerTotalSupply_;

        for (uint256 index_; index_ < _initialBalances[0].length; ++index_) {
            initialPowerTotalSupply_ += _initialBalances[0][index_];
        }

        for (uint256 index_; index_ < _initialAccounts[0].length; ++index_) {
            assertEq(
                powerToken_.balanceOf(_initialAccounts[0][index_]),
                (_initialBalances[0][index_] * powerToken_.INITIAL_SUPPLY()) / initialPowerTotalSupply_
            );
        }

        IZeroToken zeroToken_ = IZeroToken(_registrar.zeroToken());

        for (uint256 index_; index_ < _initialAccounts[1].length; ++index_) {
            assertEq(zeroToken_.balanceOf(_initialAccounts[1][index_]), _initialBalances[1][index_]);
        }
    }

    function test_setKey() external {
        IStandardGovernor standardGovernor_ = IStandardGovernor(_registrar.standardGovernor());

        address[] memory targets_ = new address[](1);
        targets_[0] = address(standardGovernor_);

        uint256[] memory values_ = new uint256[](1);

        bytes32 key_ = "TEST_KEY";
        bytes32 value_ = "TEST_VALUE";

        bytes[] memory callDatas_ = new bytes[](1);
        callDatas_[0] = abi.encodeWithSelector(standardGovernor_.setKey.selector, key_, value_);

        string memory description_ = "Update config key/value pair";

        uint256 proposalFee_ = standardGovernor_.proposalFee();

        _cashToken1.mint(_alice, proposalFee_);

        vm.prank(_alice);
        _cashToken1.approve(address(standardGovernor_), proposalFee_);

        vm.prank(_alice);
        uint256 proposalId_ = standardGovernor_.propose(targets_, values_, callDatas_, description_);

        assertEq(_cashToken1.balanceOf(_alice), 0);
        assertEq(_cashToken1.balanceOf(address(standardGovernor_)), proposalFee_);

        _warpToNextVoteEpoch();

        vm.prank(_alice);
        uint256 weight_ = standardGovernor_.castVote(proposalId_, 1);

        assertEq(weight_, 550_000);

        _warpToNextTransferEpoch();

        standardGovernor_.execute(targets_, values_, callDatas_, bytes32(0));

        assertEq(_registrar.get(key_), value_);

        assertEq(_cashToken1.balanceOf(_alice), proposalFee_);
        assertEq(_cashToken1.balanceOf(address(standardGovernor_)), 0);
    }

    function test_emergencySetKey() external {
        IEmergencyGovernor emergencyGovernor_ = IEmergencyGovernor(_registrar.emergencyGovernor());

        address[] memory targets_ = new address[](1);
        targets_[0] = address(emergencyGovernor_);

        uint256[] memory values_ = new uint256[](1);

        bytes32 key_ = "TEST_KEY";
        bytes32 value_ = "TEST_VALUE";

        bytes[] memory callDatas_ = new bytes[](1);
        callDatas_[0] = abi.encodeWithSelector(emergencyGovernor_.setKey.selector, key_, value_);

        string memory description_ = "Emergency update config key/value pair";

        vm.prank(_alice);
        uint256 proposalId_ = emergencyGovernor_.propose(targets_, values_, callDatas_, description_);

        vm.prank(_alice);
        assertEq(emergencyGovernor_.castVote(proposalId_, 1), 550_000);

        vm.prank(_bob);
        assertEq(emergencyGovernor_.castVote(proposalId_, 1), 250_000);

        emergencyGovernor_.execute(targets_, values_, callDatas_, bytes32(0));

        assertEq(_registrar.get(key_), value_);
    }
}
