// SPDX-License-Identifier: MIT
// Bomb Villain Oracle by xrpant
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IDIA {
    function getValue(string memory key) external view returns (uint128, uint128);
}

interface IBOMB {
  function detonateBomb(uint256 _bomb) external;
  function setBombTimer(uint256 _bomb, uint256 _timestamp) external;
  function bombToTimestamp(uint256 _bomb) external view returns (uint256);
  function isBombActive(uint256 _bomb) external view returns (uint8);
  function totalSupply() external view returns (uint256);
}

contract BombVillainOracle is ChainlinkClient, ConfirmedOwner {
  using Chainlink for Chainlink.Request;
  AggregatorV3Interface internal priceFeed1;
  AggregatorV3Interface internal priceFeed2;
  AggregatorV3Interface internal priceFeed3;
  AggregatorV3Interface internal priceFeed4;
  AggregatorV3Interface internal priceFeed5;
  IDIA diaContract = IDIA(0x1Fe94DfCb35a020Ca05ab94bfd6E60F14eecfa31);
  IBOMB bombContract;

  uint256 constant private ORACLE_PAYMENT = 0.01 * 10 ** 18;
  uint256 public currentRandom;
  uint256 public timeInterval;
  uint256[] public detonationCodes;
  address private oracleAddress;
  address private gameAddress;
  address[] public knownVillains;
  string[] private diaAssets;
  string private oracleJobID;
  mapping(uint256 => address) public codeToVillain;
  mapping(address => uint256) public villainToPoints;
  mapping(address => uint8) public isVillainKnown;

  event RequestRandomFulfilled(
    bytes32 indexed requestId,
    uint256 indexed random
  );

  event BombReset(
    uint256 indexed tokenID,
    uint256 indexed codeHash,
    uint256 randomNumber,
    string indexed result
  );
  
  event TimeDetonation(
      uint256 indexed bomb,
      uint256 indexed timestamp
  );

  event CodeSubmitted(
      uint256 indexed codeHash,
      address indexed villain
  );

  constructor() ConfirmedOwner(msg.sender){
    setChainlinkToken(0x5947BB275c521040051D82396192181b413227A3);
    detonationCodes = [20884705254668899239996410022713015919239154486429032189663217007220460497088,
                       10548146658542260248532830984243683142386755344354923752462670406139417080165,
                       23478311573133525241308051155044065141447189661208180297220916303554602596378,
                       29156547532998557067532744902574223546923304940341877472992800804248324996887,
                       37898100695834793214498540622292319732832020342489164302706275992777510821593,
                       20884705254668899239996454654684846512239154486429032189663217007220460497088,
                       10548146658543873543854316516516831651356755344354923752462670406139417080165,
                       23478311573139999874451926321313416151132356151613161166220916303554602596378,
                       45645465465469985570675327449025742235469233049403418774729928008042483249688,
                       37898100695834793214498540635438465465165135135165165165161235992777510821593];
    for (uint8 i=0;i<10;i++){
        codeToVillain[detonationCodes[i]] = 0xc03B9483B53c5b000Fa073D3C4549E0aEE6e2E8e;
    }
    priceFeed1 = AggregatorV3Interface(0x0A77230d17318075983913bC2145DB16C7366156);
    priceFeed2 = AggregatorV3Interface(0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743);
    priceFeed3 = AggregatorV3Interface(0x976B3D034E162d8bD72D6b9C989d545b839003b0);
    priceFeed4 = AggregatorV3Interface(0x49ccd9ca821EfEab2b98c60dC60F518E765EDe9a);
    priceFeed5 = AggregatorV3Interface(0x0c40Be7D32311b36BE365A2A220243B8A651df5E);
    diaAssets = ["BTC/USD","ETH/USD","FTM/USD","SDN/USD","KSM/USD"];
    currentRandom = 1220732953;
    oracleAddress = 0xbb5EA5A43B8bD446e9f5802350d68eCb09352012;
    oracleJobID = "bbd570fca84644ce8eb9875c341b52e5";
    gameAddress = 0x345b5E0C8ceCCCeA88a45C5E4b0f6129be6E51c2;
    timeInterval = 86400;
  }

  function setDIA(string[] memory _assets) public onlyOwner {
      diaAssets = _assets;
  }

  function setDIAContract(address _address) public onlyOwner {
      diaContract = IDIA(_address);
  }

  function setLink1(address _address) public onlyOwner {
      priceFeed1 = AggregatorV3Interface(_address);
  }

  function setLink2(address _address) public onlyOwner {
      priceFeed2 = AggregatorV3Interface(_address);
  }

  function setLink3(address _address) public onlyOwner {
      priceFeed3 = AggregatorV3Interface(_address);
  }

  function setLink4(address _address) public onlyOwner {
      priceFeed4 = AggregatorV3Interface(_address);
  }

  function setLink5(address _address) public onlyOwner {
      priceFeed5 = AggregatorV3Interface(_address);
  }

  function setOracleAddress(address _address) public onlyOwner {
      oracleAddress = _address;
  }

  function setOracleJob(string memory _jobID) public onlyOwner {
      oracleJobID = _jobID;
  }

  function setGameInfo(address _address) public onlyOwner {
      gameAddress = _address;
      bombContract = IBOMB(_address);
  }

  function setTimeInterval(uint256 _interval) public onlyOwner {
    timeInterval = _interval;
  }

  function resetVillainPoints() public onlyOwner {
      for (uint256 i = 0; i < knownVillains.length; i++) {
        villainToPoints[knownVillains[i]] = 0;
      }
  }

  function resetBomb(uint256 _bomb) external {
    require(msg.sender == gameAddress, "Only the game can call this function.");
    
    requestRandom(oracleAddress,oracleJobID);
    uint256 _code = detonationCodes[detonationCodes.length - ((currentRandom % 10) + 1)];
    villainToPoints[codeToVillain[_code]] += 1;
    uint256 _price;
    uint256 _randomHash = uint256(keccak256(abi.encodePacked(currentRandom + block.timestamp)));
    uint256 _asset = _randomHash % 5;
    uint8 _feed = uint8((_code % 2) + 1);
    int price;
    if (_feed == 1) {
        if (_asset == 0) {
          (,price,,,) = priceFeed1.latestRoundData();
          _price = uint256(price);
        } else if (_asset == 1) {
            (,price,,,) = priceFeed2.latestRoundData();
          _price = uint256(price);
        } else if (_asset == 2) {
            (,price,,,) = priceFeed3.latestRoundData();
          _price = uint256(price);
        } else if (_asset == 3) {
            (,price,,,) = priceFeed4.latestRoundData();
          _price = uint256(price);
        } else if (_asset == 4) {
            (,price,,,) = priceFeed5.latestRoundData();
          _price = uint256(price);
        }
    } else {
        (_price,) = diaContract.getValue(diaAssets[_asset]);
    }
    uint256 _combinedHash;
    if (_code > _randomHash) {
        _combinedHash = uint256(keccak256(abi.encodePacked(_code - _randomHash + _price)));
    } else {
        _combinedHash = uint256(keccak256(abi.encodePacked(_randomHash - _code + _price)));
    }
    uint256 finalRandom = (uint256(keccak256(abi.encodePacked(_combinedHash - block.timestamp))) % 1000) + 1;
    
    string memory result;

    if (finalRandom <= 800) {
      result = "Bomb Reset!";
      bombContract.setBombTimer(_bomb, block.timestamp);
    } else {
      result = "Bomb Detonated!";
      bombContract.detonateBomb(_bomb);
    }

    emit BombReset(_bomb, _code, finalRandom, result);
  }

  function submitDetonationCode(uint16 _detonationCode) public {
      uint256 _code = uint256(keccak256(abi.encodePacked(_detonationCode + block.timestamp)));
      detonationCodes.push(_code);
      codeToVillain[_code] = msg.sender;
      
      if (isVillainKnown[msg.sender] == 0) {
        isVillainKnown[msg.sender] = 1;
        knownVillains.push(msg.sender);
      }

      emit CodeSubmitted(_code, msg.sender);
  }

  function checkBombs() public {
    for (uint256 i = 1; i <= bombContract.totalSupply(); i++) {
      if (bombContract.isBombActive(i) == 1){
        if (bombContract.bombToTimestamp(i) + timeInterval < block.timestamp) {
            bombContract.detonateBomb(i);
            emit TimeDetonation(i, block.timestamp);
        } 
      }
    }
  }

  function requestRandom(address _oracle, string memory _jobId)
    private
  {
    Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32(_jobId), address(this), this.fulfillRandom.selector);
    req.add("get", "https://random-data-api.com/api/number/random_number");
    req.add("path", "number");
    sendChainlinkRequestTo(_oracle, req, ORACLE_PAYMENT);
  }

  function fulfillRandom(bytes32 _requestId, uint256 _random)
    public
    recordChainlinkFulfillment(_requestId)
  {
    emit RequestRandomFulfilled(_requestId, _random);
    currentRandom = _random;
  }

  function getChainlinkToken() public view returns (address) {
    return chainlinkTokenAddress();
  }

  function withdrawLink() public onlyOwner {
    LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
  }

  function cancelRequest(
    bytes32 _requestId,
    uint256 _payment,
    bytes4 _callbackFunctionId,
    uint256 _expiration
  )
    public
    onlyOwner
  {
    cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
  }

  function stringToBytes32(string memory source) private pure returns (bytes32 result) {
    bytes memory tempEmptyStringTest = bytes(source);
    if (tempEmptyStringTest.length == 0) {
      return 0x0;
    }

    assembly { // solhint-disable-line no-inline-assembly
      result := mload(add(source, 32))
    }
  }

  function seeGameAddress() public view returns (address) {
    return gameAddress;
  }

  function getKnownVillains() public view returns (address[] memory) {
    return knownVillains;
  }
  
}
