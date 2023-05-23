// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {ERC20} from "./ERC20.sol";
import {DepositorCoin} from "./DepositorCoin.sol";
import {Oracle} from "./Oracle.sol";

contract StableCoin is ERC20{
    DepositorCoin public depositorCoin;
    //uint256 private  constant ETH_IN_USD_PRICE = 2000; //hard-coded
    uint256 public feeRatePercentage;
    Oracle public oracle;

    uint256 public constant INITIAL_COLLATERAL_RATIO_PERCENTAGE = 10;


    constructor(uint256 _feeRatePercentage, Oracle _oracle) ERC20("Stablecoin", "STC"){
        feeRatePercentage = _feeRatePercentage;
        oracle = _oracle;
    }

    function mint() external payable {
        uint256 fee = _getFee(msg.value);
        uint256 remainingEth = msg.value- fee;
        uint256 mintStableCoinAmount =msg.value * oracle.getPrice();
        _mint(msg.sender, mintStableCoinAmount);
    }

    function burn(uint256 burnStableCoinAmount) external {
        int256 deficitOrSurplusInUsd = -_getDeficitOrSurplusInContractInUsd();
        require(deficitOrSurplusInUsd >=0, "STC: cannot burn while in deficit ");
        _burn(msg.sender, burnStableCoinAmount);

        uint256 refundingEth = burnStableCoinAmount / oracle.getPrice();
        uint256 fee = _getFee(refundingEth);
        uint256 remainingRefundingEth = refundingEth - fee;

        (bool success,)= msg.sender.call{value: remainingRefundingEth}("");
        require(success, "STC: Burn refund transaction failed");
    } 

    function _getFee(uint256 ethAmount) private view returns (uint256) {
        bool hasDepositors = address(depositorCoin) != address(0) 
        && depositorCoin.totalSupply() > 0;
        if (!hasDepositors) {
            return 0;
        }
        return(feeRatePercentage *ethAmount)/100;
    }

    function depositCollateralBuffer() external payable {
        int256 deficitOrSurPlusInUsd = _getDeficitOrSurplusInContractInUsd();

        if (deficitOrSurPlusInUsd <= 0){
            uint256 deficitInUsd = uint256(deficitOrSurPlusInUsd * -1);
            uint256 usdInEthPrice = oracle.getPrice();
            uint256 deficitInEth = deficitInUsd / usdInEthPrice;

            uint256 requiredInitialSurplusInUsd = (INITIAL_COLLATERAL_RATIO_PERCENTAGE
             * totalSupply) /100;
             uint256 requiredInitialSurplusInEth = requiredInitialSurplusInUsd /usdInEthPrice;

             require(
                msg.value >= deficitInEth + requiredInitialSurplusInEth,
                "STC: initial collateral ratio is not met"
             );

            uint256 newInitialSurplusInEth = msg.value / deficitInEth;

            uint256 newInitialSurplusInUsd = newInitialSurplusInEth * usdInEthPrice;

            depositorCoin = new DepositorCoin();

        uint256 mintDepositorCoinAmount =  newInitialSurplusInUsd;
        depositorCoin.mint(msg.sender, mintDepositorCoinAmount);
            return;
        }
        uint256 surplusInUsd = uint256(deficitOrSurPlusInUsd);
        uint256 dpcInUsdPrice = _getDPCinUsdPrice(surplusInUsd);

        uint256 mintdepositorCoinAmount = ((msg.value * dpcInUsdPrice) /
        oracle.getPrice());

        depositorCoin.mint(msg.sender, mintdepositorCoinAmount);
    }

    function withdrawCollateralBuffer(uint256 burnDepositorCoinAmount) external {
       require(
        depositorCoin.balanceOf(msg.sender)>= burnDepositorCoinAmount, 
          "STC: sender has been insufficient DPC funds");
        depositorCoin.burn(msg.sender, burnDepositorCoinAmount);

        int256 deficitOrSurplusInUsd = _getDeficitOrSurplusInContractInUsd();
        require(deficitOrSurplusInUsd >0, "STC: no funds available to withdraw");

        uint256 surplusInUsd = uint256(deficitOrSurplusInUsd);
        uint256 dpcInUsdPrice = _getDPCinUsdPrice(surplusInUsd);
        uint256 refundingUsd = burnDepositorCoinAmount/ dpcInUsdPrice;
        uint256 refundingEth = refundingUsd / oracle.getPrice();

        (bool success, ) = msg.sender.call{value: refundingEth}("");
        require(success, "STC: Withdraw refund transaction failed");
        }

    }

   function _getDeficitOrSurplusInContractInUsd() private view returns (int256){
    uint256 ethContractBalanceInUsd = 
        (address(this).balance - msg.value)* oracle.getPrice();
        uint256 totalStableCoinBalanceInUsd = totalSupply;
        int256 deficitOrSurPlus = int256(ethContractBalanceInUsd)- 
                  int256(totalStableCoinBalanceInUsd);

        return deficitOrSurPlus;
   } 

   function _getDPCinUsdPrice(uint256 surplusInUsd) private view returns (uint256) {
    return depositorCoin.totalSupply() / surplusInUsd;
   } 
}