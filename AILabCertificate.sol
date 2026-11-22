// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AI LAB 수료증 (양도 불가 NFT)
/// @notice 인원 제한이 없습니다. 발급번호(=토큰 ID)는 무작위 6자리입니다.
///         1) register  : 발급번호와 이름 지문(SHA-256)을 먼저 등록합니다. 지갑 주소가 없어도 됩니다.
///         2) issue     : 지갑 주소를 받은 분에게 NFT를 발급합니다.
///         3) reassign  : 주소를 잘못 받았거나 바뀌면 운영진이 다른 주소로 옮깁니다.
///         수료생끼리는 양도할 수 없습니다(ERC-5192).
contract AILabCertificate {
    string public constant name = "AI LAB Certificate";
    string public constant symbol = "AILAB";

    address public owner;
    string public baseURI;

    /// 발급번호 => 이름 지문. 0이면 등록되지 않은 번호입니다.
    mapping(uint256 => bytes32) public certHash;
    uint256 public registeredCount;
    uint256 public issuedCount;

    mapping(uint256 => address) private _holders;
    mapping(address => uint256) private _balances;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Locked(uint256 tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event Registered(uint256 indexed tokenId, bytes32 certHash);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error Soulbound();
    error NotRegistered(uint256 tokenId);
    error AlreadyIssued(uint256 tokenId);
    error NotIssued(uint256 tokenId);
    error ZeroAddress();
    error LengthMismatch();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(string memory baseURI_) {
        owner = msg.sender;
        baseURI = baseURI_;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ───────────── 운영진 기능 ─────────────

    /// 발급번호와 이름 지문을 등록합니다. 이미 등록된 번호도 다시 넣으면 고쳐집니다.
    /// 지문을 0으로 넣으면 등록이 취소됩니다(NFT가 발급되지 않은 번호만).
    function register(uint256[] calldata tokenIds, bytes32[] calldata hashes) external onlyOwner {
        if (tokenIds.length != hashes.length) revert LengthMismatch();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            bytes32 prev = certHash[id];
            bytes32 next = hashes[i];
            if (next == bytes32(0) && _holders[id] != address(0)) revert AlreadyIssued(id);
            if (prev == bytes32(0) && next != bytes32(0)) registeredCount++;
            if (prev != bytes32(0) && next == bytes32(0)) registeredCount--;
            certHash[id] = next;
            emit Registered(id, next);
        }
    }

    /// 등록된 발급번호로 NFT를 발급합니다.
    function issue(uint256 tokenId, address to) public onlyOwner {
        if (certHash[tokenId] == bytes32(0)) revert NotRegistered(tokenId);
        if (_holders[tokenId] != address(0)) revert AlreadyIssued(tokenId);
        if (to == address(0)) revert ZeroAddress();
        _holders[tokenId] = to;
        _balances[to] += 1;
        issuedCount++;
        emit Transfer(address(0), to, tokenId);
        emit Locked(tokenId);
    }

    /// 여러 명을 한 번에 발급합니다.
    function issueBatch(uint256[] calldata tokenIds, address[] calldata tos) external onlyOwner {
        if (tokenIds.length != tos.length) revert LengthMismatch();
        for (uint256 i = 0; i < tokenIds.length; i++) issue(tokenIds[i], tos[i]);
    }

    /// 주소 수정: 이미 발급된 NFT를 다른 주소로 옮깁니다(운영진만).
    function reassign(uint256 tokenId, address to) external onlyOwner {
        address from = _holders[tokenId];
        if (from == address(0)) revert NotIssued(tokenId);
        if (to == address(0)) revert ZeroAddress();
        _balances[from] -= 1;
        _balances[to] += 1;
        _holders[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    /// 발급 취소(소각). 등록은 남으므로 다시 issue 할 수 있습니다.
    function revoke(uint256 tokenId) external onlyOwner {
        address from = _holders[tokenId];
        if (from == address(0)) revert NotIssued(tokenId);
        _balances[from] -= 1;
        delete _holders[tokenId];
        issuedCount--;
        emit Transfer(from, address(0), tokenId);
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        baseURI = uri;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ───────────── 조회 ─────────────

    /// 발급되지 않았으면 0 주소를 돌려줍니다(확인 페이지용).
    function holderOf(uint256 tokenId) external view returns (address) {
        return _holders[tokenId];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address h = _holders[tokenId];
        if (h == address(0)) revert NotIssued(tokenId);
        return h;
    }

    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_holders[tokenId] == address(0)) revert NotIssued(tokenId);
        return string.concat(baseURI, _toString(tokenId), ".json");
    }

    function locked(uint256 tokenId) external view returns (bool) {
        if (_holders[tokenId] == address(0)) revert NotIssued(tokenId);
        return true;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 // ERC-165
            || id == 0x80ac58cd // ERC-721
            || id == 0x5b5e139f // ERC-721 Metadata
            || id == 0xb45a3c0e // ERC-5192 양도 불가
            || id == 0x49064906; // ERC-4906 메타데이터 갱신
    }

    // ───────────── 양도·승인 차단 ─────────────

    function getApproved(uint256) external pure returns (address) { return address(0); }
    function isApprovedForAll(address, address) external pure returns (bool) { return false; }
    function approve(address, uint256) external pure { revert Soulbound(); }
    function setApprovalForAll(address, bool) external pure { revert Soulbound(); }
    function transferFrom(address, address, uint256) external pure { revert Soulbound(); }
    function safeTransferFrom(address, address, uint256) external pure { revert Soulbound(); }
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure { revert Soulbound(); }

    function _toString(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 len;
        for (uint256 t = v; t != 0; t /= 10) len++;
        bytes memory b = new bytes(len);
        while (v != 0) {
            len--;
            b[len] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }
}
