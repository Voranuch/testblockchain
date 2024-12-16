
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./RoleManagement.sol";
import "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract PolicyManagement {

    RoleManagement private roleManagement;
    MockV3Aggregator public priceFeed; // Chainlink Mock price feed

    struct Policy {
        uint256 policyID;          
        string insurancePlan;            
        string basePremiumRate;
        uint256 deductible;
        uint256 insuranceCoverage;
        uint256 thirdPartyLiability;
        string[] cover;         
    }

    struct UserPolicySelection {
        uint256 policyID;
        uint256 premiumPriceETH; 
        uint256 nextDueDate; // Next payment due date (UNIX timestamp)
    }

    mapping(uint256 => Policy) public policies;
    mapping(address => UserPolicySelection[]) internal userPolicies;

    mapping(address => bool) public isPolicyHolder;
    mapping(uint256 => address[]) public policyHolders;
    

    uint256 public policyCount;
    address public premiumCollectionAddress;              

    event PolicyCreated(
        uint256 policyID,
        address indexed admin,
        string insurancePlan,
        string basePremiumRate,
        uint256 deductible,
        uint256 insuranceCoverage,
        uint256 thirdPartyLiability,
        string[] cover
    );

    event PolicySelected(address indexed user, uint256 policyID, uint256 premiumPriceETH, uint256 nextDueDate);

    // Modifier for admin access control
    modifier onlyAdmin() {
        require(roleManagement.isAdmin(msg.sender), "Access denied: You are not Admin");
        _;
    }

    // Modifier for user access control
    modifier onlyUser() {
        require(roleManagement.isUser(msg.sender), "Access denied: You are not a Policy Holder");
        _;
    }

    constructor(address _roleManagementAddress, int256 _initialPrice) {
        roleManagement = RoleManagement(_roleManagementAddress);
        priceFeed = new MockV3Aggregator(8, _initialPrice); // 8 decimal places for USD/ETH
    }

    function setPremiumCollectionAddress(address _premiumCollectionAddress) external onlyAdmin {
        premiumCollectionAddress = _premiumCollectionAddress;
    }

    /**
     * @dev Admin creates a new policy. 
     */
    function createPolicy(
        string memory _insurancePlan,
        string memory _basePremiumRate,
        uint256 _deductible,
        uint256 _insuranceCoverage,
        uint256 _thirdPartyLiability,
        string[] memory _cover
    ) external onlyAdmin {
        policyCount++;
        policies[policyCount] = Policy(
            policyCount, 
            _insurancePlan, 
            _basePremiumRate, 
            _deductible, 
            _insuranceCoverage, 
            _thirdPartyLiability, 
            _cover
        );

        emit PolicyCreated(
            policyCount, 
            msg.sender, 
            _insurancePlan, 
            _basePremiumRate, 
            _deductible, 
            _insuranceCoverage, 
            _thirdPartyLiability, 
            _cover
        );
    }

    /**
     * @dev User selects a policy.
     * Only the user can select a policy for themselves.
     */

    function selectPolicy(address _user, uint256 _policyID, uint256 _premiumInUSD) external {
    // Check if the policy exists
    require(_policyID > 0 && _policyID <= policyCount, "Policy does not exist");

    // Convert the premium from USD to ETH (or handle accordingly)
    uint256 premiumInETH = getUSDToETH(_premiumInUSD);

    // Calculate the next due date for the policy
    uint256 nextDueDate = block.timestamp + 365 days;

    // Ensure that the user is a valid user (role check can still be important)
    require(roleManagement.isUser(_user), "Access denied: You are not a valid user");

    // Mark the user as a policy holder
    isPolicyHolder[_user] = true;

    // Add the selected policy to the user's list of selected policies
    userPolicies[_user].push(UserPolicySelection(_policyID, premiumInETH, nextDueDate));

    // Emit the event to confirm the policy selection
    emit PolicySelected(_user, _policyID, premiumInETH, nextDueDate);
}

    function getUSDToETH(uint256 amountInUSD) public view returns (uint256) {
    // Fetch the latest ETH price from the price feed (e.g., Chainlink)
    (, int256 price, , , ) = priceFeed.latestRoundData();

    // Ensure the price is valid (positive value)
    require(price > 0, "Invalid price feed");

    // Convert the price from int256 to uint256
    uint256 ethPriceInUSD = uint256(price);

    // Fetch the decimals of the price feed (usually 8 decimals for USD/ETH)
    uint8 priceFeedDecimals = priceFeed.decimals();

    // Ensure the amountInUSD is correctly scaled by 10^decimals of the price feed
    uint256 amountInWei = (amountInUSD * 10 ** priceFeedDecimals) / ethPriceInUSD;

    // Return the equivalent value in Wei
    return amountInWei;
}


    /**
     * @dev View details of a specific policy.
     */
    function viewPolicy(uint256 _policyID) external view returns (
        uint256 policyID,
        string memory insurancePlan,
        string memory basePremiumRate,
        uint256 deductible,
        uint256 insuranceCoverage,
        uint256 thirdPartyLiability,
        string[] memory cover
    ) {
        require(_policyID > 0 && _policyID <= policyCount, "Policy does not exist");

        Policy storage policy = policies[_policyID];

        return (
            policy.policyID,
            policy.insurancePlan,
            policy.basePremiumRate,
            policy.deductible,
            policy.insuranceCoverage,
            policy.thirdPartyLiability,
            policy.cover
        );
    }

    /**
     * @dev View all policies that exist in the contract.
     */
    function viewAllPolicies() external view returns (Policy[] memory) {
        Policy[] memory allPolicies = new Policy[](policyCount);
        for (uint256 i = 1; i <= policyCount; i++) {
            allPolicies[i - 1] = policies[i];
        }
        return allPolicies;
    }

    /**
     * @dev View all selected policies for a specific user along with the premium price in ETH.
     */
    function getUserSelectedPolicies(address _user) external view returns (
        uint256[] memory policyIDs,
        uint256[] memory premiumPricesETH,
        uint256[] memory dueDates
    ) {
        uint256 totalPolicies = userPolicies[_user].length;
        require(totalPolicies > 0, "User has not selected any policies");

        uint256[] memory policyIDArray = new uint256[](totalPolicies);
        uint256[] memory premiumPriceArray = new uint256[](totalPolicies);
        uint256[] memory dueDatesArray = new uint256[](totalPolicies);

        for (uint256 i = 0; i < totalPolicies; i++) {
            UserPolicySelection storage userSelection = userPolicies[_user][i];
            policyIDArray[i] = userSelection.policyID;
            premiumPriceArray[i] = userSelection.premiumPriceETH;
            dueDatesArray[i] = userSelection.nextDueDate;
        }

        return (policyIDArray, premiumPriceArray, dueDatesArray);
    }
}
