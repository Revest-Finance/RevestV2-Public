// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity >=0.8.0;

interface IRewardsHandler {
    struct UserBalance {
        uint256 allocPoint; // Allocation points
        uint256 lastMul;
    }

    function receiveFee(address token, uint256 amount) external;

    function updateLPShares(uint256 fnftId, uint256 newShares) external;

    function updateBasicShares(uint256 fnftId, uint256 newShares) external;

    function getAllocPoint(uint256 fnftId, address token, bool isBasic) external view returns (uint256);

    function claimRewards(uint256 fnftId, address caller) external returns (uint256);

    function setStakingContract(address stake) external;

    function getRewards(uint256 fnftId, address token) external view returns (uint256);
}
