# private/ — 커밋되지 않는 작업 폴더

**여기에 회사 `.ovpn` 파일을 둔다.** `.gitignore` 가 이 폴더 내용 전체를
제외하므로 (이 README 만 예외) 실수로 커밋될 일이 없다.

```
private/
├── README.md          ← 이 파일만 커밋됨
└── <회사>.ovpn        ← 커밋 안 됨
```

## 왜 이 폴더가 필요한가

`.ovpn` import 는 **자동화할 수 없다.** 사내 자산 파일이라 사람이 받아와야 한다.
그 파일을 둘 일관된 자리를 정해두면, 셋업 절차와 문서가 같은 경로를 가리킬 수 있다.

## import 후에는?

`openvpn3 config-import --persistent` 로 import 하면 openvpn3 가 프로파일을
자체 저장소에 보관한다. 그 뒤로는 이 폴더의 파일이 없어도 연결된다
(원본은 재설치·재import 를 위해 남겨두는 게 좋다).

```bash
openvpn3 configs-list          # import 된 프로파일 확인
```

## 주의

- 이 폴더를 **플러그인 설치본에 기대하지 말 것.** `omarchy plugin add` 는 git 에
  있는 것만 클론하므로 여기 내용은 오지 않는다. 셋업 시점의 로컬 작업 폴더다.
- 파일을 다른 데로 옮겼다면 셋업 명령의 경로만 바꾸면 된다.
