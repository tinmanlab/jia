# Vision Ads Deploy Agent Guide

이 저장소의 배포 자동화는 `agent` 역할을 수행하도록 문서화되어 있으며, 대화형 호출만으로도 실행 흐름을 처리할 수 있습니다.

## 0) 원칙

1. 운영 URL은 `aro-vision` 하나만 유지한다.
2. 광고는 사용자 입력으로 주입된 publisher/slot만 사용한다.
3. 배포 전 점검 통과를 우선으로 한다.
4. AdSense 심사/도메인 상태는 배포 성공(HTTP 200)과 분리해 관리한다.

## 1) 기본 처리 규칙 (한마디 해석)

`vision-ads-release-hook.ps1`는 `-Intent` 문자열을 분석해 다음으로 매핑합니다.

- `배포해줘`, `진행`, `go live` → `deploy`
- `사전검사`, `준비`, `파일만`, `prepare` → `prepare`
- `미리보기`, `preview`, `테스트` → `preview`
- `현재상태`, `상태`, `별칭` → `status`
- `도움`, `help` → `help`

`deploy` 기본 값:
- `Alias = aro-vision`
- `AliasCleanupPrefix = aro-vision`
- `ExpectedUrl = https://aro-vision.vercel.app`
- `-PruneAliases = $true`

## 2) 훅 실행 우선순위

1) 사전점검 (`-RunPreflight`)  
2) 템플릿 주입 및 HTML 생성 (`new-seeds-ad-release.ps1`)  
3) 배포 (`vercel --prod`)  
4) URL probe 확인  
5) 과거 alias 정리  
6) 자동 오픈 (`-AutoOpen` 지정 시)

## 3) 사용 예시

```powershell
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "배포해줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "사전검사하고 파일만 만들어줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "미리보기로 띄워줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "진행해"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "현재 상태"
```

```powershell
pwsh .\scripts\vision-ads-release-hook.ps1 -Command deploy -Strict -AutoOpen -VerifyDeployed
```

## 4) 필수 점검 항목

- `ads.txt` 존재 및 게시자 ID 반영
- 템플릿의 `DEFAULT_AD_CONFIG` 존재
- `privacy-policy.html`, `terms-of-service.html`, `contact.html` 존재
- Vercel 인증 상태(`npx vercel whoami`)
- 생성 HTML 무결성 및 `ads.txt` 도메인 동기화

## 5) 실패/보류 가이드

- `Requires review`는 AdSense 심사 상태 메시지이며, 배포 자체 실패가 아닙니다.
- 광고 미노출은 승인/도메인/차단기(AdBlock), 슬롯 형식 오입력, 브라우저 정책 등을 순차 점검합니다.
- `-Strict`는 WARN을 FAIL로 바꿔 배포 차단(운영 안전모드)합니다.
