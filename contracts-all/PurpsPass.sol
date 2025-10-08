// SPDX-License-Identifier: UNLICENSED
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PurpsPass is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard {
    using MerkleProof for bytes32[];

    uint256 public MAX_SUPPLY = 3100;
    uint256 public MAX_MINT = 3;
    bool public isSupplyLocked = false;

    string public baseURI;
    uint256 private _nextTokenId;

    bool public isWhitelistPhase = false;
    bytes32 public merkleRoot;

    constructor() ERC721("PurpsPass", "PPASS") Ownable(msg.sender) {}

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

    function mint(
        bytes32[] calldata _merkleProof
    ) external nonReentrant returns (uint256) {
        require(totalSupply() < MAX_SUPPLY, "Max supply reached");
        require(balanceOf(msg.sender) < MAX_MINT, "Max mint reached");

        if (isWhitelistPhase) {
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
            require(
                MerkleProof.verify(_merkleProof, merkleRoot, leaf),
                "Not whitelisted"
            );
        }

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        return tokenId;
    }

    function setWhitelistPhase(bool _isWhitelistPhase) external onlyOwner {
        isWhitelistPhase = _isWhitelistPhase;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        require(!isSupplyLocked, "Supply is locked");
        MAX_SUPPLY = _maxSupply;
    }

    function setMaxMint(uint256 _maxMint) external onlyOwner {
        MAX_MINT = _maxMint;
    }

    function lockSupply() external onlyOwner {
        isSupplyLocked = true;
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
