# Synology DSM 배포 안내 (Git clone 방식)

이 문서는 Synology NAS에 TheWordCalendar API 서버를 설치하고, 휴대폰용 Android 앱을 연결하는 절차를 설명합니다. API와 데이터는 NAS에서 실행하고 APK는 Flutter와 Android SDK가 설치된 Windows PC에서 빌드합니다. DSM에서는 Container Manager와 Docker Compose를 사용합니다.

## 현재 가능한 배포 방식

**현재 이 저장소에서 실제로 설치하고 사용할 수 있는 경로는 Tailscale을 이용한 비공개 배포입니다.** NAS와 앱을 쓰는 각 휴대폰에 Tailscale을 설치하고 같은 tailnet에 연결합니다. [7절](#7-nas-연결-android-앱-만들기)의 빌드 절차와 [4절](#4-서버-상태와-api-확인)의 Serve 설정을 사용하면 됩니다.

Tailscale 없이 일반 사용자에게 앱을 공개하는 방식은 아직 구현되어 있지 않습니다. 아래 공개 접속 절은 네트워크 구성의 개요와 앞으로 필요한 개발 항목을 설명합니다. 공개 절차를 실제로 완료한 것으로 간주하면 안 됩니다. 현재 사용자 토큰은 APK에 포함되고 NAS API도 그 고정 토큰만 확인합니다. 공개 배포를 하려면 앱과 서버 인증을 바꾸고, 그 인증을 사용하는 새 APK 빌드 절차도 추가해야 합니다. 관리자 토큰은 별도로 보호해야 합니다.

NAS에 데이터와 API를 두는 것과 Firebase를 일부 인증 기능에 사용하는 것은 양립할 수 있습니다. 이 구성에서 Firebase는 익명 사용자 신원을 확인하는 용도로만 쓰고, PDF·제목·QnA·통계 데이터는 NAS에 저장합니다. Firebase ID 토큰은 클라이언트가 HTTPS로 서버에 전달하고 서버에서 검증하는 방식입니다. [Firebase ID 토큰 검증 문서](https://firebase.google.com/docs/auth/admin/verify-id-tokens)

## 준비 사항

- DSM에서 Container Manager를 설치합니다. SSH로 배포할 경우 DSM 제어판에서 SSH를 필요한 동안만 켭니다.
- Volume 1에 `docker`와 `wordcalendar-data` 공유 폴더를 만듭니다. `wordcalendar-data`에는 관리자만 접근하도록 권한을 제한하고 게스트 접근을 끕니다.
- 선택 사항으로 백업 복사본을 둘 `wordcalendar-backup` 공유 폴더를 다른 볼륨에 만들 수 있습니다. 컨테이너가 만드는 `backups/` 디렉터리는 같은 데이터 공유 폴더 안에 있으므로, NAS 디스크 고장에 대비한 별도 복사본을 대신하지 않습니다.
- 비공개 사용은 Tailscale을 NAS와 앱 사용자의 휴대폰에 설치합니다. 공개 사용은 도메인/HTTPS가 필요하며, 현재 인증 코드를 공개 배포에 사용할 수 없다는 점을 먼저 확인합니다.
- Git clone 절차에는 DSM의 Git CLI와 Docker Compose v2가 필요합니다. SSH에서 `git --version`과 `sudo docker compose version`으로 확인합니다. Git CLI를 설치할 수 없다면 저장소의 `deploy/synology/deploy_to_nas.bat`을 사용하는 Windows 복사 절차를 참고하세요.
- Windows PC에서 APK를 만들려면 Flutter SDK와 Android SDK가 필요합니다.

## 1. 저장소 내려받기

아래 예시는 저장소의 `v1` 브랜치를 `/volume1/docker/wordcalendar`에 내려받습니다. 같은 경로가 이미 있으면 다시 clone하지 말고 기존 파일과 데이터 위치부터 확인하세요.

```sh
cd /volume1/docker
git clone --branch v1 --single-branch https://github.com/booneel/HappyChurchWordCalendar.git wordcalendar
cd /volume1/docker/wordcalendar
```

## 2. 처음 설치할 때 토큰 만들기

NAS SSH에서 다음 스크립트를 실행해 사용자 토큰과 관리자 토큰을 각각 생성합니다.

```sh
cd /volume1/docker/wordcalendar
sudo sh deploy/synology/generate_tokens.sh
```

스크립트는 저장소 루트에 `.env`를 만들고 두 개의 서로 다른 무작위 토큰을 기록합니다. 파일 권한은 `600`으로 제한하며 토큰 값은 화면에 출력하지 않습니다. 기존 `.env`가 있으면 덮어쓰지 않고 중단합니다. 기존 설치에서 이 스크립트를 다시 실행하지 마세요. 토큰을 바꾸려면 먼저 기존 값을 안전하게 보관하고, 계획적으로 새 토큰을 발급해 앱도 함께 갱신해야 합니다.

토큰 두 개의 용도는 다릅니다. 현재 비공개 NAS 방식에서는 `WORDCALENDAR_NAS_TOKEN`을 일반 사용자 API 요청에 사용하고, `WORDCALENDAR_NAS_ADMIN_TOKEN`은 관리자 전용 API에 사용합니다. 공개 배포용 인증 변경이 완료되면 일반 사용자는 고정 NAS 사용자 토큰 대신 Firebase ID 토큰으로 인증하게 됩니다. 이 경우 `WORDCALENDAR_NAS_TOKEN`의 현재 용도는 없어지지만, 관리자 인증 방식을 별도로 바꾸지 않는 한 `WORDCALENDAR_NAS_ADMIN_TOKEN`은 관리자 API에 계속 사용됩니다. 공개 인증 변경은 아직 앱/API 코드에 반영되지 않았으므로, 지금 토큰 생성 절차를 건너뛰거나 기존 값을 삭제하지 마세요.

관리자 토큰도 공유 비밀번호이므로 위험이 전혀 없는 것은 아닙니다. 차이는 일반 사용자 APK 빌드에 자동으로 넣지 않고, 신뢰하는 관리자가 앱의 관리자 인증 화면에 직접 입력한다는 점입니다. 현재 앱은 이 값을 앱이 실행되는 동안 메모리에만 보관하고 앱을 다시 시작하면 다시 입력받습니다. 관리자 토큰을 아는 사람은 PDF·카탈로그·설정 변경, QnA 답변/삭제, 관리 API 사용 권한을 가질 수 있으므로 관리자에게만 전달하고 강한 난수 값을 사용하세요. 토큰이 유출되면 NAS의 `.env`에서 관리자 토큰을 교체하고 서버를 재시작한 뒤 관리자 기기에서 새 값을 입력합니다. 일반 사용자 인증을 Firebase ID 토큰으로 바꾸더라도 관리자 API는 별도 보호가 필요하며, 장기적으로 관리자를 여러 명 두거나 더 세밀한 권한 관리가 필요하면 고정 관리자 토큰 대신 Firebase 계정과 서버 측 관리자 역할 확인을 도입하는 편이 낫습니다.

토큰은 비밀번호 관리자에 보관하세요. 실제 `.env` 파일을 Git에 추가하거나 메신저·문서에 복사하지 마세요. 선택 사항인 FCM 푸시 중계를 구성하지 않는다면 `WORDCALENDAR_NAS_PUSH_URL`과 `WORDCALENDAR_NAS_PUSH_SECRET`은 빈 값으로 둡니다.

## 3. API 서버 배포 및 업데이트

처음 배포하거나 저장소 코드를 업데이트한 뒤 다음 명령을 실행합니다. 기존 Firebase 데이터를 가져올 계획이면 **먼저 6절의 내보내기와 파일 복사를 끝낸 뒤** 이 명령을 실행하세요. NAS API의 첫 시작 전에 `qna.json`과 `stats.json`을 복사해야 자동으로 SQLite로 가져옵니다.

```sh
cd /volume1/docker/wordcalendar
sudo sh deploy/synology/deploy_on_synology.sh
```

스크립트는 저장소에 있는 Compose 파일과 NAS 서버 파일을 Docker 빌드 경로로 준비하고, 데이터 공유 폴더에 `data/`와 `backups/` 디렉터리를 만듭니다. `.env`의 토큰 길이와 서로 다른 값인지 확인하고, Compose 설정을 검사한 뒤 컨테이너를 다시 빌드하고 시작합니다. `.env`와 데이터 파일은 덮어쓰지 않습니다.

컨테이너를 시작하기 전에 `/volume1/wordcalendar-data` 공유 폴더를 만들어야 합니다. 데이터 이전을 하는 경우에는 기존 Firebase 데이터 내보내기 파일을 **서버 첫 시작 전에** 데이터 폴더에 복사해야 합니다. 서버가 처음 시작될 때 `qna.json`과 `stats.json`은 SQLite로 가져오며, 이미 생성된 SQLite 데이터베이스 위에 이전 파일을 덮어쓰면 안 됩니다.

저장소에서 최신 코드를 받는 업데이트 절차는 다음과 같습니다. 로컬에서 직접 수정한 내용이 있는지 먼저 확인하고, 중요한 데이터는 별도 위치에 백업한 뒤 진행하세요.

```sh
cd /volume1/docker/wordcalendar
git status --short
git pull --ff-only origin v1
sudo sh deploy/synology/deploy_on_synology.sh
```

`git pull --ff-only`가 로컬 변경 때문에 거부되면 강제로 덮어쓰지 마세요. 변경 내용을 별도로 검토하거나 백업한 뒤 업데이트합니다. 새 버전 적용 전후에 `/volume1/wordcalendar-data` 전체를 다른 저장소에도 복사해 두는 것을 권장합니다. 컨테이너를 다시 빌드하거나 재시작해도 이 공유 폴더는 유지되지만, 공유 폴더 삭제나 Container Manager의 프로젝트 정리 기능은 데이터를 지울 수 있습니다.

## 4. 서버 상태와 API 확인

NAS SSH에서 컨테이너 상태와 최근 로그를 확인합니다.

```sh
cd /volume1/docker/wordcalendar
sudo docker compose ps
sudo docker compose logs --tail=100 wordcalendar-api
```

정상이라면 `wordcalendar-api`가 실행 중이어야 합니다. 토큰 값을 셸 명령에 직접 붙여 넣지 않고 `.env`에서 읽어 두 API를 확인할 수 있습니다.

```sh
cd /volume1/docker/wordcalendar
WORDCALENDAR_NAS_TOKEN=$(awk -F= '$1=="WORDCALENDAR_NAS_TOKEN" {print $2}' .env)
WORDCALENDAR_NAS_ADMIN_TOKEN=$(awk -F= '$1=="WORDCALENDAR_NAS_ADMIN_TOKEN" {print $2}' .env)
curl -i -H "Authorization: Bearer $WORDCALENDAR_NAS_TOKEN" http://127.0.0.1:8787/api/settings/pdf
curl -i -H "Authorization: Bearer $WORDCALENDAR_NAS_ADMIN_TOKEN" http://127.0.0.1:8787/api/admin/check
unset WORDCALENDAR_NAS_TOKEN WORDCALENDAR_NAS_ADMIN_TOKEN
```

두 요청 모두 HTTP `200`을 반환해야 합니다. 잘못된 토큰은 `401` 또는 `403`이어야 합니다. 연결 거부가 나오면 컨테이너 상태와 로그, NAS의 `127.0.0.1:8787` 포트 사용 여부를 확인하세요.

Compose는 포트 `8787`을 NAS 내부의 `127.0.0.1`에만 연결합니다. 인터넷에 이 포트를 직접 공개하지 마세요. Synology용 Tailscale을 NAS에 설치하고, Tailscale 관리자 콘솔에서 MagicDNS와 HTTPS 인증서를 활성화한 뒤 같은 tailnet으로 로그인합니다. DSM SSH에서 Serve를 켭니다. 아래 경로가 NAS의 Tailscale 설치 위치와 다르면 [Tailscale Synology 설치 안내](https://tailscale.com/docs/integrations/synology)에서 실제 경로를 확인하세요.

```sh
sudo /var/packages/Tailscale/target/bin/tailscale serve --bg http://127.0.0.1:8787
sudo /var/packages/Tailscale/target/bin/tailscale serve status
```

`serve status` 출력에 표시되는 `https://<NAS이름>.<tailnet>.ts.net` 주소를 복사합니다. 앱을 설치할 각 휴대폰에도 Tailscale을 설치하고 같은 tailnet에 연결해야 이 주소를 열 수 있습니다. `Funnel`은 켜지 마세요. 현재 구성의 Tailscale Serve는 tailnet 안에서만 접근할 수 있습니다. [Tailscale Serve와 Funnel 안내](https://tailscale.com/docs/features/tailscale-funnel)

휴대폰이나 외부 PC의 브라우저에서 다음 주소로 API가 도달하는지 확인할 수 있습니다. 사용자 토큰을 보내지 않았으므로 `401` 응답이 정상입니다. 인증서 오류, NAS 로그인 화면, `404` 응답이 나오면 HTTPS/프록시 호스트 이름과 경로를 확인하세요.

```text
https://<NAS이름>.<tailnet>.ts.net/api/settings/pdf
```

## 5. Tailscale 없이 일반 사용자에게 공개하려면

이 절은 공개 배포를 위한 네트워크 구성과 필수 보안 변경을 설명합니다. **인증 코드 변경과 새 앱 빌드가 완료되기 전에는 DNS, 포트 포워딩, 역방향 프록시를 설정해 API를 공개하지 마세요.** 주소를 공개하는 일만으로는 앱 인증이 안전해지지 않습니다.

다음 내용은 지금 순서대로 실행할 수 있는 완성된 설치 과정이 아닙니다. 절의 설명 순서와 실제 진행 순서가 다릅니다. 먼저 5-3의 앱/API 인증과 공개용 APK 빌드 기능을 개발하고 검증한 다음, 5-1과 5-2의 주소 및 네트워크 설정을 마치고, 마지막으로 5-4에 따라 배포합니다. 5-3은 개발이 필요한 항목을 설명하며 DSM 설정만으로 완료할 수 없습니다.

### 5-1. 인증 구현 후 필요한 주소와 네트워크 조건 확인

1. `example.com`처럼 본인이 관리하는 도메인 또는 Synology DDNS 주소를 준비합니다. 앱 전용 호스트 이름으로 `api.example.com`을 정하는 것을 권장합니다.
2. 집 인터넷 회선이 외부에서 들어오는 연결을 허용하는지 확인합니다. 공유기 WAN 주소와 외부 IP가 다르거나 WAN 주소가 `100.64.0.0/10`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` 대역이면 CGNAT 또는 상위 공유기 뒤에 있을 수 있습니다. 이 경우 공유기 포트 포워딩만으로 외부 접속이 되지 않을 수 있으므로 ISP에 공인 IPv4 제공 여부를 문의하거나 터널 서비스를 사용합니다.
3. 고정 IP가 아니면 DNS/DDNS가 현재 집 공인 IP를 계속 가리키도록 구성합니다. DNS가 엉뚱한 주소를 가리키면 앱은 NAS에 연결할 수 없습니다.

### 5-2. 인증 구현 후 라우터와 DSM에서 HTTPS 연결 구성

아래는 공인 IP로 직접 접속할 수 있는 경우의 일반적인 구성입니다. 공유기와 DSM 버전에 따라 메뉴 이름이 다를 수 있습니다.

1. 도메인의 DNS에 `api.example.com`을 공인 IP로 연결하는 `A` 레코드를 설정합니다. IPv6를 별도로 구성하지 않는다면 잘못된 `AAAA` 레코드는 만들지 않습니다. DDNS를 쓰는 경우에도 `api` 호스트 이름이 NAS가 있는 집의 현재 주소를 가리키는지 확인합니다.
2. 공유기에서 **외부 TCP 443 → NAS의 내부 TCP 443**만 포워딩합니다. DSM 관리 포트(보통 5000/5001)와 API 포트 8787은 인터넷으로 포워딩하지 않습니다. DSM 방화벽을 사용한다면 필요한 HTTPS 연결을 허용합니다.
3. DSM 제어판에서 `로그인 포털` 또는 `응용 프로그램 포털 > 역방향 프록시`로 이동해 새 규칙을 만듭니다. 소스는 HTTPS, 호스트 이름 `api.example.com`, 포트 `443`으로 설정합니다. 대상은 HTTP, 호스트 `127.0.0.1`, 포트 `8787`로 설정합니다. 이렇게 하면 Compose의 로컬 전용 포트 연결을 유지하면서 DSM 프록시가 내부 API로 전달합니다. DSM의 메뉴 위치는 버전에 따라 달라질 수 있습니다. [Synology 역방향 프록시 안내](https://kb.synology.com/en-au/DSM/help/DSM/AdminCenter/application_appportalias?version=6)
4. DSM 인증서 화면에서 `api.example.com`에 유효한 인증서를 발급하거나 기존 인증서를 연결하고, 해당 인증서를 위 역방향 프록시 호스트에 지정합니다. Let's Encrypt 발급 방식에 따라 외부 TCP 80 포트가 도메인 소유 확인에 필요할 수 있습니다. 인증서 발급 뒤에는 가능하면 앱 통신은 HTTPS만 사용하도록 합니다.
5. 외부 모바일 네트워크에서 `https://api.example.com/api/settings/pdf`로 접속합니다. TLS 인증서가 유효하고 JSON 형태의 `401` 응답이 오면 요청이 NAS API 경로까지 도달한 것입니다. `https://api.example.com/`의 응답은 API 도달 여부를 확인하는 데 쓰지 마세요. 현재 서버에는 루트(`/`) 확인 경로가 없습니다. 이 확인은 네트워크 연결만 확인하며 앱 인증이 성공한다는 뜻은 아닙니다.

공인 IP/포트 포워딩을 사용할 수 없는 CGNAT 환경이면 Synology가 지원하는 터널이나 별도 공개 프록시를 검토해야 합니다. 예를 들어 Cloudflare Tunnel은 NAS가 외부로 터널을 연결하는 구조로 포트 포워딩 없이 공개 호스트 이름을 제공할 수 있지만, 도메인/DNS와 Cloudflare 설정이 추가로 필요합니다. 어떤 터널을 쓰더라도 현재 APK 토큰 문제를 해결한 뒤 공개해야 합니다.

### 5-3. 먼저 구현해야 할 앱/API 인증 (현재 미구현)

아래 항목은 사용자가 DSM 설정만으로 완료할 수 있는 설치 절차가 아닙니다. 저장소의 앱·API 코드를 먼저 수정하고 검증해야 합니다. 현재 이 인증 방식은 구현되어 있지 않습니다.

공개 앱에는 모든 설치본이 공유하는 고정 사용자 토큰을 넣지 않습니다. 이 저장소의 현재 방식은 `WORDCALENDAR_NAS_TOKEN`을 APK 빌드 옵션으로 넣고 API가 그 토큰을 확인합니다. 이 토큰은 사용자별 계정이 아니라 **앱을 설치한 모두가 공유하는 하나의 비밀번호**입니다. APK는 사용자의 휴대폰에 전달되는 파일이므로 내부 값을 분석해 토큰을 추출할 수 있습니다. HTTPS는 휴대폰과 서버 사이를 오가는 통신을 암호화하지만, APK 안에 들어간 고정 토큰까지 숨겨 주지는 않습니다.

공개 앱에 이 토큰을 쓰면 APK를 받은 누구나 사용자 API에 요청할 수 있고, 요청이 어느 사용자에게서 왔는지 서버가 구분하기 어렵습니다. 토큰을 외부에 공개하거나 악용 가능성이 생겼을 때 토큰을 교체하면, 정당한 사용자 앱도 새 토큰을 포함해 전부 다시 빌드하고 재배포해야 합니다. Firebase ID 토큰 방식은 앱 설치별 익명 사용자 신원을 서버가 검증하게 하므로, 공용 비밀번호 하나를 모든 APK에 넣지 않아도 됩니다. 이 방식도 사용자 식별/접근 통제의 기반일 뿐이므로 요청 제한과 서버 측 검증을 함께 적용해야 합니다.

구현 작업에는 다음 항목이 포함되어야 합니다.

1. Firebase Console의 Authentication에서 프로젝트의 **익명 로그인** 제공자를 활성화합니다. 앱은 익명 계정을 통해 기기별 Firebase ID 토큰을 받습니다. 사용자에게 회원 가입이나 Tailscale 설치를 요구하지 않는 방식입니다.
2. Flutter NAS API 클라이언트가 각 요청의 `Authorization: Bearer ...`에 고정 NAS 토큰 대신 Firebase ID 토큰을 넣도록 변경합니다. 토큰 갱신을 처리하고 PDF 다운로드를 포함한 모든 사용자 API 요청에 적용해야 합니다.
3. NAS API에 Firebase Admin SDK 기반 ID 토큰 검증을 추가합니다. 서버는 토큰의 서명, 만료, Firebase 프로젝트를 검증하고 UID를 사용해 요청자를 식별합니다. 검증 실패/토큰 없음은 거부해야 합니다.
4. Firebase 서비스 계정 자격 증명은 NAS의 보호된 비밀 파일로 제공하고, Git 저장소·APK·공유 문서에 넣지 않습니다. 서버 컨테이너에서만 읽을 수 있게 권한을 제한합니다.
5. 관리자 API는 사용자 API와 별도 권한을 계속 적용합니다. 관리자 토큰은 APK에 포함하지 않고, 강한 관리자 토큰 및 가능하면 관리자 네트워크/IP 제한을 사용합니다.
6. UID/IP 기준 요청 제한, 입력 크기 제한, 백업 및 로그 점검을 적용합니다. Firebase App Check를 추가하면 비정상 클라이언트 요청을 줄이는 데 도움이 되지만, ID 토큰 검증을 대체하지는 않습니다.
7. 인증된 요청/거부 요청, QnA 작성/답변, PDF 다운로드·업로드, 앱의 재로그인과 토큰 갱신을 테스트한 뒤에만 공개 URL을 배포합니다.

현재 `build_nas_apk.bat`도 공개 인증 방식과 맞지 않습니다. 이 스크립트는 사용자 토큰을 입력받아 APK에 포함합니다. 따라서 인증 코드만 바꿔도 충분하지 않으며, 공개 인증을 사용하는 APK 빌드 절차도 함께 구현해야 합니다. 둘 다 구현·검증되기 전에는 공개 주소를 현행 APK에 연결하지 마세요.

### 5-4. 사용자에게 앱 전달

공개 HTTPS 주소와 사용자 인증 검증을 모두 완료한 뒤 외부 배포용 APK를 새로 빌드합니다. 이 구성이 끝나면 앱을 설치한 휴대폰은 Wi-Fi나 LTE/5G로 인터넷에 연결하고 공개 HTTPS 주소에 접속하면 됩니다. 사용자는 Tailscale을 설치하거나 NAS와 같은 네트워크에 연결할 필요가 없습니다. 단, NAS가 켜져 있고 인터넷에서 접속 가능해야 하며, 인증 코드 변경과 공개 주소 설정이 먼저 완료되어야 합니다. Android APK를 직접 전달하면 설치 시 출처를 알 수 없는 앱 허용이 필요할 수 있습니다. 여러 사용자에게 지속 배포할 계획이라면 Google Play 내부/비공개 테스트 또는 정식 등록도 고려하세요. 앱 업데이트 때는 같은 앱 서명 키를 계속 사용해야 기존 앱 위에 업데이트할 수 있습니다.

관리 및 긴급 점검 목적으로 Tailscale을 NAS에 계속 둘 수 있습니다. 이 경우에도 공개 앱 트래픽은 도메인의 HTTPS 프록시를 이용하고, NAS SSH/DSM 관리 화면을 공개 인터넷에 노출하지 않습니다.

## 6. 기존 Firebase 데이터 이전

이 절은 현재 저장소에 설정된 Firebase 프로젝트 데이터를 Windows PC로 내보내 NAS에 처음 가져오는 방법입니다. 새 NAS를 빈 데이터로 시작한다면 이 절은 건너뛰어도 됩니다. 이전 중에는 기존 앱에서 PDF·제목·QnA 변경을 잠시 멈추고, Firebase 원본과 서비스 계정 파일을 안전하게 보관하세요.

먼저 Firebase Console에서 읽기 권한이 있는 서비스 계정 JSON을 준비합니다. 서비스 계정 파일을 저장소 폴더, NAS 웹 폴더 또는 Git에 두지 마세요. 프로젝트 루트 PowerShell에서 아래를 실행합니다. `--bucket`은 현재 저장소 설정값이며, Firebase Console의 실제 Storage 버킷이 다르면 그 값으로 바꾸세요. PDF 파일명이 다르면 `--pdf-name "실제파일명.pdf"`도 추가합니다.

```powershell
cd D:\my_portfolio\Date-Pdf
python -m pip install firebase-admin
python python/export_firebase_to_nas.py --service-account C:\secure\firebase-service-account.json --bucket thewordcalendar-f768c.firebasestorage.app --output C:\secure\wordcalendar-export
```

내보내기에 성공하면 `C:\secure\wordcalendar-export\data`에 `current.pdf`, `pdf_metadata.json`, `catalog.json`, `settings.json`, `qna.json`, `stats.json`이 생성됩니다. 이 `data` 폴더 안의 파일을 File Station 또는 SMB로 NAS의 `/volume1/wordcalendar-data/data/`에 복사합니다. `wordcalendar-data` 공유 폴더와 `data` 하위 폴더가 없으면 먼저 만드세요.

**이 데이터 복사를 NAS API의 첫 시작 전에 완료해야 합니다.** 최초 실행 때 서버가 `qna.json`과 `stats.json`을 SQLite로 가져옵니다. 이미 서버를 한 번이라도 시작했다면 이 JSON을 덮어쓰지 마세요. 현재 NAS 데이터를 백업하고 별도 이전 절차를 준비해야 합니다. NAS 데이터가 Firebase 데이터와 일치하는지 확인하고 복원 시험을 마칠 때까지 Firebase 원본과 내보내기 사본을 보존하세요.

새로 설치해 가져올 데이터가 없다면 서버는 빈 카탈로그로 시작할 수 있습니다. 다만 사용자가 PDF를 열려면 `/volume1/wordcalendar-data/data/current.pdf`가 필요합니다. 앱을 NAS에 연결한 뒤 관리자 기능으로 PDF를 업로드하거나, 검증된 초기 PDF를 서버를 시작하기 전에 데이터 폴더에 배치하세요. PDF 제목 카탈로그도 새 PDF 내용과 일치하는지 확인해야 합니다.

## 7. NAS 연결 Android 앱 만들기

저장소 루트의 `deploy/synology/build_nas_apk.bat`을 Flutter와 Android SDK가 설치된 Windows PC에서 실행합니다.

```cmd
deploy\synology\build_nas_apk.bat
```

스크립트가 HTTPS 기본 주소와 NAS 사용자 토큰을 묻습니다. 현재는 `https://wordcalendar-nas.example.ts.net` 같은 Tailscale Serve 주소를 입력합니다. 주소 끝에 `/wordcalendar`나 API 경로를 붙이지 않습니다. 토큰 입력은 화면에 표시되지 않지만 빌드 스크립트는 사용자 토큰을 APK에 포함합니다. APK를 신뢰하는 비공개 사용자에게만 전달하고, Tailscale 없는 공개 배포에는 이 스크립트를 사용하지 마세요. 공개 배포는 앞 절의 앱/API 인증 변경과 공개용 APK 빌드 기능이 구현된 뒤에만 가능합니다.

관리자 토큰은 APK 빌드 명령에 넣지 않습니다. 관리자는 앱의 관리자 인증 화면에서 `.env`의 `WORDCALENDAR_NAS_ADMIN_TOKEN`을 입력합니다. NAS 관리자 토큰은 앱을 다시 시작하면 다시 입력해야 합니다.

NAS 모드에서는 서버가 관리자 토큰을 확인하고 관리자 API를 제한합니다. Firebase 기본 모드의 승인 코드 `123456`은 앱 안에서만 비교하는 값이므로 서버 인증 수단이 아닙니다. Firebase 모드 앱을 공개 배포하려면 관리자 인증과 Firestore/Storage 권한을 서버 측에서 별도로 구성해야 합니다.

성공하면 다음 APK가 생성됩니다.

```text
build\app\outputs\flutter-apk\wordcalendar-nas.apk
```

비공개 방식은 휴대폰에서 Tailscale을 켜고 앱을 엽니다. NAS 오프라인 안내가 사라지는지, 날짜별 PDF와 QnA가 표시되는지 확인합니다. 공개 방식은 Tailscale 없이 모바일 네트워크에서 앱을 열고 로그인/토큰 갱신, PDF, QnA, 관리자 기능을 각각 확인합니다. 공개 방식 테스트는 위의 인증 코드 변경을 배포한 후에만 진행합니다. 사용자 토큰이 노출되면 NAS `.env`의 토큰을 교체하고 컨테이너를 다시 만든 다음, 새 사용자 토큰으로 APK를 다시 빌드해 배포해야 합니다. 관리자 토큰이 노출되면 관리자 토큰만 교체하고 컨테이너를 다시 만든 뒤 새 토큰을 관리자 기기에 입력합니다. 토큰은 HTTPS나 Tailscale을 대체하지 않습니다.

## 8. 제목 추출 API 키 안내

NAS 서버 운영과 NAS용 APK 빌드에는 OpenAI API 키가 필요하지 않습니다. 앱 관리자 화면의 제목 카탈로그 기능은 PDF에서 제목을 분석하는 데 기기 내 OCR/레이아웃 분석을 사용합니다.

별도로 제공되는 `python` 폴더의 AI 제목 추출 도구를 사용할 때만 OpenAI API 키가 필요합니다. Windows PC에서 `python/01_setup.bat`을 실행한 뒤 `python/.env` 파일의 `OPENAI_API_KEY`에 키를 저장하면, 이후 제목 추출을 다시 실행할 때 사용할 수 있습니다. 키를 Git에 올리거나 NAS의 `.env`, APK, 검수용 HTML/JSON에 넣지 마세요. 이 키는 PC에서 OpenAI API를 호출할 때만 쓰이며, NAS 배포에는 포함되지 않습니다. AI 추출 기능을 다시 사용하지 않고 이미 만든 제목을 수동 검수하거나 앱으로 가져오기만 한다면 키를 저장해 둘 필요가 없습니다.

API 사용량에 따라 비용이 발생할 수 있으므로 전체 추출 전에 `python/02_test_3_titles.bat`으로 일부 날짜만 실행해 결과와 사용량을 확인하세요. 전체 분석 후 `python/04_build_review.bat`으로 검수 페이지를 만들고, 제목과 이미지 영역을 사람이 확인한 다음 JSON을 앱의 `말씀 제목 카탈로그 > JSON 제목 파일 불러오기`에서 저장합니다. 검수 HTML은 브라우저에서 로컬로 열리며 API 키를 담지 않습니다.

## 9. Windows에서 파일을 복사해 배포하는 대안

Git CLI를 DSM에 설치하지 않는 경우 Windows OpenSSH의 `ssh`와 `scp`를 사용해 NAS 서버 파일만 복사하는 `deploy/synology/deploy_to_nas.bat`을 실행할 수 있습니다.

```cmd
deploy\synology\deploy_to_nas.bat
```

이 배치 파일은 NAS에 이미 준비된 `/volume1/docker/wordcalendar/.env`, `app/` 폴더, `/volume1/wordcalendar-data`를 확인하고 서버 파일을 복사한 뒤 컨테이너를 다시 빌드합니다. `.env`나 Firebase 내보내기 데이터는 복사하지 않습니다. 사용자 앱 APK는 별도로 `build_nas_apk.bat`으로 PC에서 빌드해 휴대폰에 설치합니다. DSM은 API와 데이터를 호스팅하며 Android APK를 빌드하지 않습니다.
