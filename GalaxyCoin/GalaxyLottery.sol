pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Oracle.sol";
import "./ReentrancyGuard.sol";

interface IGalaxy {
    function adminFeePercent() external view returns (uint256);
    function liquidityFeePercent() external view returns (uint256);
}


contract GalaxyLottery is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address public admin;
    address public tokenContract;
    
    uint256 public ticketPrice;
    uint256 public adminFee;  // multiply with 100 (20% = 2000)
    uint256 public firstWinnerShare;
    uint256 public secondWinnerShare;
    uint256 public thirdWinnerShare;
    uint256 public lastCreatedLotteryId;
    uint256 public usersPerLottery;
    uint256 public startBlock;
    
    uint256 nonce;
    Oracle oracle;
    
    Lottery[] public lotteryList;
    
    mapping (uint256 => address[]) private lotteryUsers;
    mapping (uint256 => uint256) private lotteryBalance;
    
    struct Lottery{
        uint256 lotteryId;
        uint256 createdAt;
        address winner1;
        address winner2;
        address winner3;
    }
    
    
    // modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin is allowed");
        _;
    }
    
    
    // events
    event CreateLotteryEvent(uint256 indexed _lotteryId,  uint256 _timestamp);
    event JoinLotteryEvent(uint256 indexed _lotteryId, address indexed _user, uint256 _timestamp);
    event WinnerEvent(uint256 indexed _lotteryId, address indexed _winner, uint256 _winnerPosition, uint256 _winAmount, uint256 _timestamp);
    
    constructor(
        address _tokenContract, 
        uint256 _ticketPrice, 
        uint256 _adminFee, 
        uint256 _firstWinnerShare, 
        uint256 _secondWinnerShare, 
        uint256 _thirdWinnerShare,
        uint256 _usersPerLottery,
        address _oracleAddress
        ) {
        require(_firstWinnerShare.add(_secondWinnerShare).add(_thirdWinnerShare).add(_adminFee) == 10000, "Total Distribution Percentage should be 100");
        admin = msg.sender;  
        tokenContract = _tokenContract;
        oracle = Oracle(_oracleAddress);
        ticketPrice = _ticketPrice;
        adminFee = _adminFee;
        firstWinnerShare = _firstWinnerShare;
        secondWinnerShare= _secondWinnerShare;
        thirdWinnerShare = _thirdWinnerShare;
        usersPerLottery = _usersPerLottery;
        startBlock = block.number;
        lotteryList.push(Lottery(0, 0, address(0x0), address(0x0), address(0x0)));
        _createLottery();
    }
    
    
    // function to update ticket fee
    function updateTicketFee(uint256 _ticketPrice) external onlyAdmin {
        ticketPrice = _ticketPrice;
    }
    
    // function winner and admin distribution
    function updateDistributionPercentage(uint256 _firstWinnerShare, uint256 _secondWinnerShare, uint256 _thirdWinnerShare, uint256 _adminFee) 
    external onlyAdmin {
        require(_firstWinnerShare.add(_secondWinnerShare).add(_thirdWinnerShare).add(_adminFee) == 10000, "Total Distribution Percentage should be 100");
        adminFee = _adminFee;
        firstWinnerShare = _firstWinnerShare;
        secondWinnerShare= _secondWinnerShare;
        thirdWinnerShare = _thirdWinnerShare;
    }
    
    // function to create new lottery
    function _createLottery() internal {
        lastCreatedLotteryId = lotteryList.length;

        delete lotteryUsers[lastCreatedLotteryId];
        
        lotteryList.push(Lottery(lastCreatedLotteryId, block.timestamp, address(0x0), address(0x0), address(0x0)));

        emit CreateLotteryEvent(lastCreatedLotteryId, block.timestamp);
    }
    
    // function to join open lottery
    function joinLottery() external {
        IERC20(tokenContract).safeTransferFrom(msg.sender, address(this), ticketPrice);

        uint256 adminDeduction = _percent(ticketPrice, IGalaxy(tokenContract).adminFeePercent());
        uint256 liquidityDeduction = _percent(ticketPrice, IGalaxy(tokenContract).liquidityFeePercent());
        uint256 TaxDeductedAmount = ticketPrice.sub(adminDeduction).sub(adminDeduction).sub(liquidityDeduction);
        
        lotteryUsers[lastCreatedLotteryId].push(msg.sender);
        lotteryBalance[lastCreatedLotteryId] = lotteryBalance[lastCreatedLotteryId].add(TaxDeductedAmount);

        emit JoinLotteryEvent(lastCreatedLotteryId, msg.sender, block.timestamp);

        if (checkJoinedNumber() >= usersPerLottery) {
            distributeRewards(lastCreatedLotteryId);
        }
    }
    
    // function to check users joined in a lottery
    function checkJoinedNumber() public view returns(uint256) {
        return lotteryUsers[lastCreatedLotteryId].length;
    }
    
    // function to distribute rewards
    function distributeRewards(uint256 _lotteryId) internal {
        require(lotteryUsers[_lotteryId].length >= 3, "Atleast 3 Users Required");
        
        _getWinners(lotteryUsers[_lotteryId].length, _lotteryId);
        
        require(lotteryList[_lotteryId].winner1 != address(0x0), "winner1 address zero is invalid");
        require(lotteryList[_lotteryId].winner2 != address(0x0), "winner2 address zero is invalid");
        require(lotteryList[_lotteryId].winner3 != address(0x0), "winner3 address zero is invalid");
        
        uint256 totalLotteryAmount = lotteryBalance[_lotteryId];
        require(IERC20(tokenContract).balanceOf(address(this)) >= totalLotteryAmount, "Contract doesn't have enough balance");

        uint256 firstWinnersAmount = _percent(totalLotteryAmount, firstWinnerShare);
        uint256 secondWinnersAmount = _percent(totalLotteryAmount, secondWinnerShare);
        uint256 thridWinnersAmount = _percent(totalLotteryAmount, thirdWinnerShare);
        
        IERC20(tokenContract).safeTransfer(lotteryList[_lotteryId].winner1, firstWinnersAmount);
        IERC20(tokenContract).safeTransfer(lotteryList[_lotteryId].winner2, secondWinnersAmount);
        IERC20(tokenContract).safeTransfer(lotteryList[_lotteryId].winner3, thridWinnersAmount);
        IERC20(tokenContract).safeTransfer(admin, totalLotteryAmount.sub(firstWinnersAmount).sub(secondWinnersAmount).sub(thridWinnersAmount));
        
        emit WinnerEvent(_lotteryId, lotteryList[_lotteryId].winner1, 1, firstWinnersAmount, block.timestamp);
        emit WinnerEvent(_lotteryId, lotteryList[_lotteryId].winner2, 2, secondWinnersAmount, block.timestamp);
        emit WinnerEvent(_lotteryId, lotteryList[_lotteryId].winner3, 3, thridWinnersAmount, block.timestamp);
        
        delete lotteryList[_lotteryId];
        delete lotteryUsers[_lotteryId];

        _createLottery();
    }
    
    // function to get winners of a lottery
    function _getWinners(uint256 _mod, uint256 _lotteryId) internal {
        uint256 rand1 = _randModulus(_mod);
        uint256 rand2 = _randModulus(_mod);
        uint256 rand3 = _randModulus(_mod);
        
        while(rand2 == rand1) {
            rand2 = _randModulus(_mod);
        }
        while(rand3 == rand1 || rand3 == rand2) {
            rand3 = _randModulus(_mod);
        }
        
        uint256 createdAt = lotteryList[_lotteryId].createdAt;
        address winner1 = lotteryUsers[_lotteryId][rand1];
        address winner2 = lotteryUsers[_lotteryId][rand2];
        address winner3 = lotteryUsers[_lotteryId][rand3];
        
        lotteryList[_lotteryId] = Lottery(_lotteryId, createdAt, winner1, winner2, winner3);
    }
    
    // helper function to generate random number
    function _randModulus(uint256 _mod) internal returns(uint256) {
        uint256 rand = uint256(keccak256(abi.encodePacked(nonce, oracle.rand(), block.timestamp, block.difficulty, msg.sender))) % _mod;
        nonce++;
        return rand;
    }
    
    // helper function to count percentage of amount 
    function _percent(uint256 _amount, uint256 _fraction) internal pure returns(uint256) {
        return ((_amount).mul(_fraction)).div(10000);
    }

    // Function to withdraw BNB 
    function withdrawAmount(address _to, uint256 _amount) external onlyAdmin nonReentrant {
        require(_to != address(0), "_to is Zero Address");
        uint256 balance = address(this).balance;
        require(balance >= _amount, "Insufficient balance");
        
        payable(_to).transfer(balance);
    }

    // Function to withdraw GLXY tokens 
    function withdrawTokens(address _to, uint256 _amount) external onlyAdmin nonReentrant {
        require(_to != address(0), "_to is Zero Address");
        uint256 balance = IERC20(tokenContract).balanceOf(address(this));
        require(balance >= _amount, "Insufficient balance");
        
        IERC20(tokenContract).safeTransfer(_to, _amount);
    }
}