# Seeds of Seeing Ad-Ready Deploy Pipeline

이 파이프라인은 `files/recursive_vision_v9_deploy.html`을 기반으로 다음을 자동화합니다.

1. 광고 슬롯 기본값 주입
2. 신규 html 파일 생성
3. Vercel 배포(선택)

## 사용법

이 파이프라인은 실행파일을 추가로 만들지 않고 **Skill-set 형태(단일 훅 스크립트)로 운영**합니다.

```powershell
# 기본값으로 신규 파일 생성
pwsh .\scripts\new-seeds-ad-release.ps1
```

```powershell
# 배포를 위해 생성과 동시에 실행(옵션)
pwsh .\scripts\vision-ads-release-hook.ps1 -Command deploy
```

```powershell
# 한마디만으로 실행: 대화형 intent 매핑
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "배포해줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "진행해"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "사전검사만"
```

```powershell
# 광고 슬롯과 퍼블리셔 ID를 바꿔서 생성
pwsh .\scripts\new-seeds-ad-release.ps1 `
  -VariantName "vision-portfolio" `
  -PublisherId "ca-pub-8263634312399744" `
  -SlotA "8077959277" `
  -SlotB "1561704738" `
  -OutputName "recursive_vision_custom.html"
```

```powershell
# 생성 후 바로 배포하려면
pwsh .\scripts\new-seeds-ad-release.ps1 -RunDeploy
```

`-Alias`를 비우면 `-VariantName` 기준으로 `aro-<variant>`이 자동 적용됩니다.

`-Alias`는 대상 URL의 이름표입니다.
`aro-vision` 같은 기본명은 사람이 읽기 쉬운 "운영 URL"용으로, `aro-vision-live` 같은 값은 별도 점검/실험용 캠페인 명칭입니다.
즉, 2개가 생기는 건 서로 다른 별칭으로 배포했기 때문입니다.

### 추천 Hook 모드(검증 + 자동 배포)

```powershell
# 검증 + 배포 + aro-vision만 남기기
pwsh .\scripts\vision-ads-release-hook.ps1 -VariantName "vision-portfolio" -RunDeploy:$true -VerifyDeployed:$true -PruneAliases:$true
```

또는 자연어 모드로 단일 규칙 호출:

```powershell
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "배포해줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "미리보기로 띄워줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "사전검사하고 파일만 만들어줘"
pwsh .\scripts\vision-ads-release-hook.ps1 -Intent "현재 상태"
```

명령형 모드:

```powershell
pwsh .\scripts\vision-ads-release-hook.ps1 -VariantName "vision-portfolio" -Command deploy
pwsh .\scripts\vision-ads-release-hook.ps1 -VariantName "vision-portfolio" -Command prepare
pwsh .\scripts\vision-ads-release-hook.ps1 -VariantName "vision-portfolio" -Command preview
pwsh .\scripts\vision-ads-release-hook.ps1 -Command status
```

- `-RunPreflight` : 배포 전 체크 수행(기본 true)
- `-ProgressFile` : 진행 체크리스트 파일 경로 (있으면 TODO 항목 카운트)
- `-RequireCleanProgress` : TODO 존재 시 배포 차단
- `-FailOnWarning` : 경고를 실패로 처리해 배포 차단
- `-ExpectedUrl` : 배포 후 probe 대상 URL 직접 지정(없으면 별칭 URL로 자동 확인)
- `-Strict` : WARN를 실패로 처리하고 TODO 클린을 강제하는 운영 모드 (`$true`/`$false`)
- `-AutoOpen` : 배포 성공 후 브라우저 자동 열기 (`$true`/`$false`)
- `-PruneAliases` : 배포 중 `AliasCleanupPrefix` 접두사별 과거 alias 정리(기본 true)
- `-AliasCleanupPrefix` : 삭제 대상 alias 접두사 지정(생략 시 해당 source의 모든 alias 정리, `aro-vision`만 남김)

## 출력 보증 포인트

- `ads.txt`는 루트에 `ads.txt`가 있어야 함
- 새 html에는 기본 광고 설정 블록이 주입됨
- 루트 `privacy-policy.html`, `terms-of-service.html`, `contact.html` 페이지가 준비되어야 함

## 운영 체크리스트

1. 생성 파일 확인 후 `https://aro-vision.vercel.app`에서 수동 렌더 확인
2. Google AdSense `Requires review` 상태 점검
3. 승인 완료 후 배포
4. 광고 미노출 시 광고차단기/시크릿 모드/`ads.txt`/슬롯 형식 점검
