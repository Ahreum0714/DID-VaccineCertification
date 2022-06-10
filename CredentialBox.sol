// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

// 특정 함수를 관리자만 사용할 수 있도록 설정하는 함수
abstract contract OwnerHelper {
    address private owner;  // 관리자

    // 관리자가 변경되었을 때 이전 관리자의 주소와 새로운 관리자의 주소를 로그로 남김
  	event OwnerTransferPropose(address indexed _from, address indexed _to); 

    // 함수 실행 전에 require(함수를 실행시키는 사람이 관리자인지) 확인
  	modifier onlyOwner {
		require(msg.sender == owner);
		_; // require 통과하면 함수 실행
  	}

  	constructor() {
		owner = msg.sender;  // 초기 owner는 컨트랙트 실행자
  	}

    // transferOwnership: owner를 변경하는 함수 | _to: (변경할)새로운 owner주소
  	function transferOwnership(address _to) onlyOwner public {
        require(_to != owner);  // _to가 변경 전 owner가 아니고,
        require(_to != address(0x0)); // _to의 주소가 0이 아니라면,
    	owner = _to;  // owner를 새로운 owner로 변경한다
    	emit OwnerTransferPropose(msg.sender, _to);  // owner 변경 이벤트에 대한 로그를 남기기 위해 이전 owner주소와 변경된 새 owner주소를 emit(방출)한다
  	}
}

// 스마트컨트랙트에서 issuer를 컨트롤하는 함수: owner만 issuer 추가 및 삭제 기능
abstract contract IssuerHelper is OwnerHelper {
    mapping(address => bool) public issuers;

    event AddIssuer(address indexed _issuer);
    event DelIssuer(address indexed _issuer);

    // onlyIssuer를 상속받은 함수는 require 검증을 통과한 뒤 함수 실행
    modifier onlyIssuer {
        require(isIssuer(msg.sender) == true);  // 함수 실행자(msg.sender)가 issuer인지 확인
        _;
    }

    constructor() {
        issuers[msg.sender] = true;
    }

    function isIssuer(address _addr) public view returns (bool) {
        return issuers[_addr];
    }

    // issuer 추가 기능은 onlyOwner로 제한 = owner만 추가 가능
    function addIssuer(address _addr) onlyOwner public returns (bool) {
        require(issuers[_addr] == false);
        issuers[_addr] = true;
        emit AddIssuer(_addr);  // 추가된 issuer 로그 기록을 남긴다
        return true;
    }

    // issuer 삭제 기능은 onlyOwner로 제한 = owner만 삭제 가능
    function delIssuer(address _addr) onlyOwner public returns (bool) {
        require(issuers[_addr] == true);
        issuers[_addr] = false;
        emit DelIssuer(_addr);  // 삭제된 issuer 로그 기록을 남긴다
        return true;
    }
}

contract CredentialBox is IssuerHelper {
    uint256 private idCount;  // credential이 만들어지는 index를 위한 카운터
    mapping(uint8 => string) private vaccineEnum;  // 백신 제조사를 uint8키와 string값으로 매핑

    // VC를 구현하기 위한 구조체
    struct Credential{
        uint256 id; 
        address issuer;
        uint8 vaccineType; // 백신 제조사
        uint8 shotNum;  // 백신 접종 차수
        string value;      // credential에 포함되어야 하는 암호화된 정보 (JSON형태)
        uint256 createDate;
    }

    mapping(address => Credential) private credentials;

    constructor() {
        idCount = 1;  // credential 순서를 위해 1부터 시작
        vaccineEnum[0] = "Pfizer";     // 화이자
        vaccineEnum[1] = "Moderna";    // 모더나
        vaccineEnum[2] = "AstraZeneca";// 아스트라제네카
        // vaccineEnum[3] = "Janssen";    // 얀센
    }

    // issuer가 holder(_vaccineAddress)에게 credential을 발행하는 함수, onlyIssuer를 통과해야만 실행 가능
    function claimCredential(address _vaccineAddress, uint8 _vaccineType, string calldata _value) onlyIssuer public returns(bool) {
        // credential 발행을 위해 credential 구조체 선언 (블록체인에 영향을 미쳐야 하므로 memory가 아닌 storage로 선언)
		    Credential storage credential = credentials[_vaccineAddress];
        // credential.id가 0으로 처음 작성되는지 검증하고
        require(credential.id == 0);
        // credential 구조체에 맞게 idCount와 파라미터 데이터를 할당
        credential.id = idCount;
        credential.issuer = msg.sender;
        credential.vaccineType = _vaccineType;
        credential.shotNum = 1;
        credential.value = _value;
        credential.createDate = block.timestamp;  // credential을 클레임한 시간 저장
        
        idCount += 1;

        return true;
    }

    // holder 주소를 받아 VC 확인하는 함수
    function getCredential(address _vaccineAddress) public view returns (Credential memory){
        return credentials[_vaccineAddress];
    }

    // 백신 타입 추가 함수
    function addVaccineType(uint8 _type, string calldata _value) onlyIssuer public returns (bool) {
        require(bytes(vaccineEnum[_type]).length == 0);  // 백신 타입에 해당하는 타입이 없으면,
        vaccineEnum[_type] = _value;  // 새로운 타입(_type)을 키로 갖는 값(_value)을 할당한다
        return true;
    }

    // 해당 타입을 키로 갖는 백신 타입을 반환
    function getVaccineType(uint8 _type) public view returns (string memory) {
        return vaccineEnum[_type];
    }

    // 백신 접종 차수 증가 함수
    function addShot(address _vaccineAddress) onlyIssuer public returns (bool) {
        require(credentials[_vaccineAddress].shotNum >= 1);
        credentials[_vaccineAddress].shotNum += 1;
        return true;
    }

    // 백신 접종 여부 확인 함수
    function isVaccinated(address _vaccineAddress) onlyIssuer public view returns (bool) {
        if(credentials[_vaccineAddress].shotNum >= 1) return true;
        else return false;
    }

    // 백신 접종 2주 경과 확인 함수 (접종 완료 시점: 2주)
    function checkTwoWeeks(address _vaccineAddress) onlyIssuer public view returns (bool) {
        if((block.timestamp - credentials[_vaccineAddress].createDate) > 2 weeks)
            return true;
        else
            return false;
    }
}
