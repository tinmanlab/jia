# Seeds of Seeing - Ad-Ready Deployment

`files/recursive_vision_v9_deploy.html` 템플릿을 기준으로 광고 슬롯 주입, 보안/법적 체크, 배포를 자동화하기 위한 실행 파이프라인입니다.

## 운영 원칙

- 단일 운영 URL은 `aro-vision` 하나만 유지
- API 키/토큰은 코드에 하드코딩되지 않고 사용자 입력값으로만 전달
- 배포 전 사전체크와 배포 후 probe를 통해 접근/노출 이슈를 점검
- 광고 채움 미완료 시 AdSense 심사, 슬롯/도메인 승인, 광고차단기 가능성부터 점검

## 핵심 파일

- `files/recursive_vision_v9_deploy.html`
  - 광고 설정이 들어가는 기본 템플릿
- `scripts/vision-ads-release-hook.ps1`
  - 대화형/명령형 훅
  - 사전점검, HTML 생성, 배포, 미리보기, 상태 조회를 한 번에 수행
- `scripts/new-seeds-ad-release.ps1`
  - 템플릿 주입 + Vercel config 갱신 + 배포 실행
- `scripts/SEEDS_AD_RELEASE_PIPELINE.md`
  - 실행 시나리오, 옵션 가이드
- `agent.md`
  - 운영용 실행 규칙(자동화 규약) 정리본
- `ads.txt`
  - 광고 발행자 검증 파일
- `privacy-policy.html`, `terms-of-service.html`, `contact.html`
  - 정책 페이지(정적)
- `vercel.json`
  - rewrite/header 정책

## 실행 예시

### 1) 한마디로 실행(권장)

```powershell
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "배포해줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "사전검사하고 파일만 만들어줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "미리보기로 띄워줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "현재 상태"
```

### 2) 명령형 실행

```powershell
pwsh .\scripts\vision-ads-release-hook.ps1 -Command prepare
pwsh .\scripts\vision-ads-release-hook.ps1 -Command deploy -Strict -AutoOpen
pwsh .\scripts\vision-ads-release-hook.ps1 -Command preview -Alias "aro-vision-preview"
```

### 3) 광고 슬롯만 변경해 파일 생성

```powershell
pwsh .\scripts\new-seeds-ad-release.ps1 `
  -VariantName "vision-portfolio" `
  -PublisherId "ca-pub-8263634312399744" `
  -SlotA "8077959277" `
  -SlotB "1561704738" `
  -OutputName "vision-portfolio.html"
```

## 배포 규칙

- 배포 기본 alias: `aro-vision.vercel.app`
- 미리보기 alias: `aro-vision-preview.vercel.app` (또는 커스텀 alias)
- 배포 후 URL probe는 `-VerifyDeployed`로 수행하고, 필요시 `-AutoOpen`으로 자동 브라우저 열기
- `-PruneAliases`는 동일 소스에 연결된 과거 alias를 정리해 혼선 URL를 줄임

## 사전/사후 체크리스트

- `DEFAULT_AD_CONFIG` 블록 주입 및 주입값 일치
- `ads.txt` 존재 및 게시자 ID 포함
- 정책 페이지 존재 (`privacy-policy.html`, `terms-of-service.html`, `contact.html`)
- Vercel 로그인 상태 확인
- 생성 HTML 존재성/무결성
- 하드코딩 API 키 패턴 탐지

## 배포 URL

- 운영 URL: [https://aro-vision.vercel.app](https://aro-vision.vercel.app)
