// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.19;

// Force Foundry to compile AdaptiveCurveIrm artifact needed by deployCode in tests.
import {AdaptiveCurveIrm} from "../../lib/vault-v2/lib/morpho-blue-irm/src/adaptive-curve-irm/AdaptiveCurveIrm.sol";

contract ForceCompileAdaptiveCurveIrm {
    function creationCodeLength() external pure returns (uint256) {
        return type(AdaptiveCurveIrm).creationCode.length;
    }
}
