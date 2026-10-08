# TheWordCalendar: Synology DS1825+ 설치와 앱 연결

이 프로젝트는 날짜별 PDF 보기, 제목 카탈로그, 조회수, Q&A, 관리자 PDF 교체를 제공한다. 기본 빌드는 Firebase를 사용한다. `WORDCALENDAR_BACKEND=nas`로 빌드하면 Flutter 앱이 `python/nas_api.py`의 FastAPI 서버에 연결한다. NAS 서버는 PDF와 JSON 파일, SQLite를 `/data`에 저장한다. 실제 DS1825+에 접속해 설치한 상태는 아니며, 아래 순서는 NAS 소유자가 DSM에서 수행해야 한다.

NAS Container Manager 프로젝트 폴더 이름은 `/volume1/docker/wordcalendar`로 사용한다. 데이터/백업 공유 폴더 이름은 구분을 위해 `wordcalendar-data`, `wordcalendar-backup`으로 유지한다. Windows 소스 저장소 명령은 현재 PC의 실제 경로 `D:\my_portfolio\Date-Pdf`를 기준으로 한다.

기존 NAS가 이미 `datepdf-data` 공유 폴더를 사용 중이면 빈 `wordcalendar-data` 공유 폴더를 만들어 곧바로 실행하지 않는다. 먼저 API를 중지하고 백업한 뒤 기존 데이터를 새 공유 폴더로 옮기고, 새 compose 경로를 확인한 다음 다시 시작한다.

## 처음 설치하는 순서

아래 순서대로 진행하면 NAS에 PDF API를 띄우고 휴대폰 앱을 연결할 수 있다. NAS 주소 예시는 실제 Tailscale 주소로 바꾸고, 비밀 토큰은 각자 생성한다.

1. 새 디스크만 대상으로 저장소 풀/볼륨을 만들고 DSM을 최신 안정 버전으로 업데이트한다. 디스크에 기존 데이터가 있으면 먼저 다른 저장소로 복사한다.
2. DSM 관리자 계정과 MFA, 자동 차단을 설정하고 공유기 포트 포워딩을 만들지 않는다. 개인 관리자 계정이 정상 로그인되는지 확인한 다음 기본 `admin` 계정을 끈다.
3. `docker`, `wordcalendar-data`, `wordcalendar-backup` 공유 폴더를 표에 적힌 볼륨에 만들고 일반 사용자 및 guest 권한을 확인한다.
4. PC에서 `deploy/synology/generate_tokens.bat`을 실행한다. 사용자 토큰과 관리자 토큰을 각각 비밀번호 관리자에 보관한다. FCM 알림 중계도 쓸 때만 세 번째 push secret을 보관한다.
5. NAS에 프로젝트 파일을 복사하고 `/volume1/docker/wordcalendar/.env`를 작성한 뒤 Container Manager 프로젝트를 시작한다. 첫 PDF 데이터가 없으면 앱은 연결되더라도 PDF를 표시할 수 없다.
6. NAS 내부에서 두 API 확인 명령이 성공하는지 확인한다. NAS와 휴대폰에 Tailscale을 설치하고 같은 tailnet에 로그인한 뒤 Serve HTTPS 주소에서 API를 다시 확인한다.
7. 사용자 토큰을 넣어 NAS 모드 APK를 빌드하고 설치한다. 앱에서 날짜/PDF, 제목, 조회수, Q&A를 테스트하고 관리자 토큰은 관리자 모드에서 별도로 입력한다.
8. Hyper Backup 작업을 만들고 외부 저장소에도 백업을 복제한 뒤 복원 시험을 한다.

NAS를 아직 보유하지 않았다면 1~6단계는 완료할 수 없다. 이 PC에서는 소스 테스트와 로컬 API 동작까지만 검증하며 실제 DSM 권한, Tailscale 네트워크, 디스크 복구는 NAS에서 확인해야 한다.

## 1. 디스크 계획

| 용도 | 물리 디스크 | DSM 설정 | 대략적인 사용 가능 용량 |
| --- | --- | --- | --- |
| 주 저장소 `/volume1` | 4 TB × 4 | 저장소 풀 1, SHR-1, Btrfs 볼륨 1 | 약 12 TB(표기 단위로 약 10.9 TiB, 파일 시스템 예약분 제외) |
| 보조 저장소 `/volume2` | 20 TB × 1 | 저장소 풀 2, Basic, Btrfs 볼륨 2 | 약 20 TB(약 18.2 TiB, 예약분 제외) |

4 TB 4개를 같은 풀에 넣어 1개 고장을 견디게 한다. 20 TB를 4 TB 풀에 섞지 않는다. 단일 20 TB 디스크는 고장 시 전체가 사라질 수 있으므로 `/volume2`는 *두 번째 사본*이며 유일한 보관 장소가 아니다. 랜섬웨어·도난·화재는 같은 NAS의 두 볼륨에 영향을 준다. 중요한 데이터는 별도 USB 디스크, 다른 NAS 또는 클라우드에 세 번째 사본을 둔다. 4 TB 4개에 SHR-2를 택하면 두 디스크 고장을 견디지만 용량이 약 8 TB로 준다. 현재 용도라면 SHR-1 + 보조/외부 백업이 균형이 좋다. 기존 디스크에 데이터가 있으면 풀 생성 전에 다른 장소로 백업한다. 새 풀 생성은 대상 디스크를 초기화한다.

1. DS1825+와 디스크의 정확한 모델이 [Synology 호환 목록](https://www.synology.com/en-global/compatibility?model=DS1825%2B&search_by=drives)에 있는지 확인한다. DSM/펌웨어를 최신 안정 버전으로 업데이트하고 각 디스크 SMART 상태를 확인한다.
2. DSM `저장소 관리자 > 저장소`에서 **새 저장소 풀 1**을 만든다. 4 TB 네 개만 선택, RAID 유형 `SHR (1개 디스크 보호)`를 선택한다. 이 풀에 **볼륨 1**, `Btrfs`, 가능한 용량 전체를 만든다. 풀 생성·검사·동기화 완료까지 기다린다.
3. 같은 화면에서 20 TB 한 개만 골라 **저장소 풀 2**, 유형 `Basic`, **볼륨 2** `Btrfs`를 만든다. `/volume1`과 `/volume2` 번호는 생성 순서에 따라 확인한다. 다르면 아래 경로도 실제 번호에 맞춘다.
4. `저장소 관리자 > HDD/SSD`에서 디스크 SMART 빠른 검사를 주기적으로, 확장 검사를 분기별 등 저사용 시간에 예약한다. `저장소 관리자 > 저장소 > 전역 설정/데이터 스크러빙`에서 스크러빙을 지원하는 SHR 풀 1에 월 1회 저사용 시간으로 예약한다. 단일 디스크 Basic 풀 2는 데이터 스크러빙 대상이 아니다. `wordcalendar-data` 공유 폴더를 만들 때 Btrfs 데이터 체크섬을 켜고, `Snapshot Replication`에서 해당 공유 폴더를 하루 1회/30일 보관 등으로 설정한다. 메뉴 이름은 DSM 버전에 따라 다를 수 있다. 스냅샷·RAID는 백업을 대체하지 않는다.

## 2. DSM에서 폴더와 패키지 만들기

`제어판 > 공유 폴더 > 생성`으로 아래 공유 폴더를 만든다. 공유 폴더마다 실제 저장 위치(볼륨)를 확인한다. `docker`에는 Container Manager를 사용하는 관리자 계정만 읽기/쓰기 권한을 준다. `wordcalendar-data`는 컨테이너가 접근해야 하므로 관리자만 쓰기 권한을 갖게 하고, 데이터 이동/업데이트 작업에 사용할 별도 NAS 계정만 필요한 기간에 권한을 준다. `guest`와 불필요한 사용자/그룹 권한을 제거한다. Btrfs 데이터 체크섬은 `wordcalendar-data` 공유 폴더 생성 화면에서 켠다(생성 후 켤 수 없는 DSM 구성도 있으므로 처음 만들 때 설정). File Station에서 하위 폴더를 만든다.

```text
/volume1/docker/wordcalendar/            # Container Manager 프로젝트 폴더
  compose.yaml
  .env                         # NAS에서 직접 생성. Git에 올리지 않음
  app/
    Dockerfile.nas
    nas_api.py
    nas_requirements.txt
/volume1/wordcalendar-data/               # 공유 폴더: 서버 영구 데이터
  data/
    current.pdf                 # 최초 배포 전 Firebase에서 가져오기
    catalog.json                # 최초 이전 시 선택
    settings.json               # 최초 이전 시 선택
    qna.json                    # 최초 시작 전 이전용
    stats.json                  # 최초 시작 전 이전용
    wordcalendar.sqlite3        # 서버가 생성
  backups/                      # 서버가 PDF/JSON 교체 전 사본 생성
/volume2/wordcalendar-backup/             # Hyper Backup 대상 공유 폴더
```

공유 폴더 이름은 `docker`, `wordcalendar-data`, `wordcalendar-backup`이다. `docker`와 `wordcalendar-data`는 볼륨 1, `wordcalendar-backup`은 볼륨 2를 고른다. `data`, `backups`, `app`은 File Station 하위 폴더다. `백업` 폴더는 컨테이너에 연결하지 않는다. `패키지 센터`에서 **Container Manager**, **Hyper Backup**, **Snapshot Replication**, **Security Advisor**, 원격 접속 시 **Tailscale**을 설치한다. DS1825+에서 Container Manager 사용 가능 여부는 설치 전 DSM 패키지 센터에서 확인한다.

## 3. Firebase 데이터 이전

데이터를 이전하는 동안 기존 앱에서 PDF/제목/Q&A 변경을 잠시 중지한다. 먼저 Firebase의 Storage PDF와 Firestore `pdf_catalog/current`, `pdf_settings/config`, `pdf_documents/current`, `qna`, `page_stats`를 별도 백업한다. PC에서 Google Cloud/Firebase 서비스 계정 JSON을 안전하게 받아 다음 명령을 실행한다. 계정 파일은 프로젝트 저장소나 NAS 웹 공유 폴더에 넣지 않는다.

```powershell
cd D:\my_portfolio\Date-Pdf
python -m pip install firebase-admin
python python/export_firebase_to_nas.py --service-account C:\secure\firebase-service-account.json --bucket thewordcalendar-f768c.firebasestorage.app --output C:\secure\wordcalendar-export
```

현재 앱에 설정된 Firebase 프로젝트 ID는 `thewordcalendar-f768c`, Storage 버킷은 `thewordcalendar-f768c.firebasestorage.app`이다. Firebase Console `프로젝트 설정 > 일반`에서 실제 프로젝트 ID와 `Storage` 화면의 버킷 이름을 확인한다. 다른 Firebase 프로젝트의 데이터를 이전한다면 `--bucket` 값을 그 프로젝트의 실제 버킷 이름으로 바꾼다. 서비스 계정에는 해당 Firebase 프로젝트의 Firestore 읽기 및 Cloud Storage 객체 읽기 권한이 필요하다. Firebase Storage에서 PDF 파일명이 `365일 매일묵상말씀.pdf`와 다르면 스크립트에 `--pdf-name "실제 파일명.pdf"`를 추가한다.

`C:\secure\wordcalendar-export\data`의 파일을 File Station/SMB로 `/volume1/wordcalendar-data/data/`에 복사한다. **서버 첫 시작 전에** `qna.json`과 `stats.json`을 복사해야 SQLite에 자동 이관된다. 이미 서버를 시작했다면 데이터베이스를 임의로 덮어쓰지 말고 NAS 백업 후 별도 이전 절차를 잡는다. Firebase 원본은 NAS 데이터와 제목/질문/조회수를 대조하고 복원 시험을 마칠 때까지 보존한다. 서비스 계정과 복사본은 민감한 데이터이므로 접근을 제한한다.

## 4. 서버 배포

### NAS 토큰 만들기와 배치

토큰은 NAS API가 요청자를 확인하는 비밀번호처럼 동작한다. **사용자 토큰**은 앱의 일반 기능(Q&A 읽기/질문 등록 포함)에 쓰고, **관리자 토큰**은 PDF 교체·설정/제목 수정·Q&A 답변 같은 쓰기 권한을 확인하는 데 쓴다. 두 값은 서로 달라야 하며 각각 32자 이상이어야 한다. `deploy/synology/generate_tokens.bat`을 실행하면 사용자 토큰, 관리자 토큰, push relay secret이 각각 생성된다. 처음 두 값은 항상 쓰고, 세 번째 값은 FCM 중계를 설정할 때만 쓴다. 생성값은 화면에 출력되므로 안전한 비밀번호 관리자에 옮기고 터미널 기록/공유 화면에 남기지 않는다. Python 3가 없는 PC에서는 각 토큰에 아래 명령을 별도로 실행한다.

```powershell
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

각 명령의 결과를 사용자 토큰, 관리자 토큰으로 나눠 저장한다. Python 3가 없으면 Python 3을 설치하거나 `generate_tokens.bat`이 표시하는 안내를 따른다. 실제 값을 README, 메신저, Git 저장소에 붙여 넣지 않는다.

File Station에서 NAS 공유 폴더 `docker` 아래 `wordcalendar` 폴더와 그 안의 `app` 폴더를 만든다. NAS에서 SSH를 잠시 켜고 PC PowerShell에서 `ssh DSM관리자계정@NAS_IP`로 접속한다. 아래 편집 명령으로 `.env`를 만든다. `vi` 편집기에서 각 값은 실제 생성값으로 바꾸고, FCM 중계를 쓰지 않으면 push 두 줄은 빈 값으로 둔다. 실제 값은 이 README에 붙여 넣지 않는다.

```sh
cd /volume1/docker/wordcalendar
sudo vi .env
```

`vi`에서는 `i`를 눌러 입력하고, 저장할 때 `Esc`를 누른 뒤 `:wq`와 Enter를 입력한다. 파일 권한을 제한하고 SSH 접속을 끝낸다.

```dotenv
WORDCALENDAR_NAS_TOKEN=사용자_토큰_값
WORDCALENDAR_NAS_ADMIN_TOKEN=관리자_토큰_값
WORDCALENDAR_NAS_PUSH_URL=
WORDCALENDAR_NAS_PUSH_SECRET=
```

`sudo chmod 600 /volume1/docker/wordcalendar/.env`를 실행해 관리자 외 계정에서 읽을 수 없게 한다. 필요하면 DSM의 `제어판 > 사용자 및 그룹 > 고급 > 사용자 홈/권한`과 `docker` 공유 폴더 ACL도 확인한다. SSH는 배포 후 끈다. `deploy/synology/env.example`은 자리표시자이므로 NAS에 그대로 복사해 사용하지 않는다.

`compose.yaml`이 이 `.env`를 컨테이너에 전달한다. 토큰을 바꾼 뒤에는 NAS 프로젝트 폴더에서 `sudo docker compose up -d --force-recreate`를 실행해 컨테이너를 다시 만든다. 실제 `.env`는 NAS에만 두고 Git에 올리지 않는다.

| 토큰 | 사용 위치 | 권한/주의 |
| --- | --- | --- |
| `WORDCALENDAR_NAS_TOKEN` 사용자 토큰 | NAS `.env`와 Flutter APK 빌드 명령 | 앱 일반 API 접근용. APK에 포함되므로 APK를 받은 사람이 값을 추출할 수 있다. 모든 앱 설치가 같은 값을 공유한다. |
| `WORDCALENDAR_NAS_ADMIN_TOKEN` 관리자 토큰 | NAS `.env`와 앱 관리자 코드 입력 화면 | 관리자 API 전용. **APK 빌드 명령에 넣지 않는다.** 관리자 기기에서 관리자 모드에 들어갈 때 직접 입력하며 앱을 다시 시작하면 재입력한다. |
| `WORDCALENDAR_NAS_PUSH_SECRET` 중계 비밀값 | NAS `.env`와 `functions/.env`의 `NAS_PUSH_SECRET` | NAS 서버와 Cloud Function 사이의 인증용. 앱 빌드에 넣지 않는다. |

사용자 토큰이 노출되면 NAS `.env`의 사용자 토큰을 새 값으로 바꾸고 컨테이너를 재시작한 다음, 새 사용자 토큰으로 APK를 다시 빌드해 사용자 기기에 배포한다. 관리자 토큰이 노출되면 관리자 토큰만 새 값으로 바꾸고 컨테이너를 재시작한 뒤 관리자 기기에서 새 토큰을 입력한다. 토큰은 VPN/Tailscale과 HTTPS를 대신하지 않는다.

1. PC에서 File Station으로 NAS `docker/wordcalendar` 폴더를 연다. 이 저장소의 `deploy/synology/compose.yaml`을 해당 폴더로, `python/Dockerfile.nas`, `python/nas_api.py`, `python/nas_requirements.txt`를 그 안 `app` 폴더로 복사한다. 최종 파일 경로는 `/volume1/docker/wordcalendar/compose.yaml`, `/volume1/docker/wordcalendar/app/Dockerfile.nas`, `/volume1/docker/wordcalendar/app/nas_api.py`, `/volume1/docker/wordcalendar/app/nas_requirements.txt`여야 한다. `.env`는 위에서 NAS에 직접 만든다.
2. SSH에서 `sudo chmod 600 /volume1/docker/wordcalendar/.env`를 실행한다. 프로젝트와 데이터 폴더는 관리자 외의 계정이 읽거나 수정하지 못하도록 DSM 공유 폴더 권한을 확인한다. 초기 PDF/JSON도 컨테이너에서 읽을 수 있어야 한다.
3. `Container Manager > 프로젝트 > 생성`에서 프로젝트명 `wordcalendar`, 경로 `/volume1/docker/wordcalendar`, `compose.yaml` 사용을 선택한다. 이미지 빌드와 시작을 선택한다. CLI를 쓰면 `cd /volume1/docker/wordcalendar` 후 `sudo docker compose up -d --build`를 실행한다. `sudo docker compose ps`에서 `wordcalendar-api`가 실행 중인지 확인하고 `sudo docker compose logs --tail=100 wordcalendar-api`로 시작 오류를 확인한다. 처음 빌드는 인터넷에서 Python 컨테이너 이미지를 내려받으므로 NAS의 인터넷/DNS가 작동해야 한다.
4. 호스트 포트는 `127.0.0.1:8787`에만 열린다. NAS SSH에서 아래처럼 확인한다. Windows에서는 `curl.exe`를 사용한다.

```sh
curl -i -H 'Authorization: Bearer <USER_TOKEN>' http://127.0.0.1:8787/api/settings/pdf
curl -i -H 'Authorization: Bearer <ADMIN_TOKEN>' http://127.0.0.1:8787/api/admin/check
```

둘 다 200이어야 하고 잘못된 토큰은 401 또는 403이어야 한다. 파일 교체 시 `.../app/`에 새 코드를 복사하고 `sudo docker compose up -d --build`를 다시 실행한다. **Container Manager의 프로젝트 `정리/Clean` 또는 공유 폴더 삭제는 데이터 보존을 확인하기 전 사용하지 않는다.** 컨테이너 재시작만으로 `/volume1/wordcalendar-data`는 유지된다.

### Windows 배치 파일로 NAS 배포/실행

저장소에는 NAS 토큰 생성과 파일 전송/서버 시작을 돕는 배치 파일이 있다. NAS 초기 디스크/DSM/공유 폴더 설정, Tailscale 설치, 비밀 `.env` 작성은 먼저 위 절차대로 한 번 직접 한다.

1. 탐색기에서 `deploy\synology\generate_tokens.bat`을 실행한다. 사용자 토큰, 관리자 토큰, 푸시 중계 비밀값이 출력된다. 사용자/관리자 토큰은 항상 따로 보관하고 push 값은 FCM 중계를 설정할 때만 보관한다. 이 창을 공유하거나 화면을 캡처하지 않는다.
2. NAS에서 SSH를 켜고 NAS 공유 폴더 `docker/wordcalendar/app`과 `wordcalendar-data`를 만든다. NAS `/volume1/docker/wordcalendar/.env`에 토큰을 입력하고 권한을 `600`으로 제한한다. 이 `.env`는 BAT가 전송하거나 덮어쓰지 않는다.
3. Windows에 `OpenSSH Client`가 설치되어 있고, PC에서 `ssh DSM계정@NAS_IP`로 로그인할 수 있는지 확인한다. 저장소 탐색기에서 `deploy\synology\deploy_to_nas.bat`을 더블클릭하거나 저장소 루트에서 아래 명령을 실행한다.

```cmd
deploy\synology\deploy_to_nas.bat
```

4. 프롬프트에 `DSM계정@NAS_IP` 또는 NAS의 Tailscale IP/이름을 입력한다. SSH 호스트 확인 질문이 뜨면 DSM에서 확인한 NAS에 접속 중인지 확인한 뒤 수락한다. NAS 로그인 인증 후 `sudo` 암호를 입력하면 BAT가 `compose.yaml`, Dockerfile, API 소스를 NAS로 복사하고 `docker compose up -d --build`로 빌드/실행한 다음 컨테이너 상태를 표시한다. 처음 실행에서는 NAS가 컨테이너 이미지를 내려받으므로 인터넷 연결이 필요하다.
5. 완료 메시지가 나와도 API 인증 확인은 별도로 한다. 앞의 `curl` 두 명령이 각각 200을 반환하는지 확인한다. 코드 변경 후에도 같은 BAT를 다시 실행하면 서버 코드를 복사하고 컨테이너를 재빌드한다.

이 BAT는 Windows OpenSSH의 `ssh`와 `scp`, DSM SSH 서비스, NAS의 Container Manager/Compose CLI가 필요하다. `.env`, Firebase 내보내기 PDF/JSON, 디스크·볼륨 생성, 공유 폴더 생성, 방화벽 및 Tailscale 설정은 수행하지 않는다. Container Manager에서 프로젝트를 처음 만들기 전에도 BAT로 compose를 실행할 수 있지만, `wordcalendar-data` 공유 폴더와 `.env`가 반드시 먼저 있어야 한다. BAT가 실패하면 NAS 프로젝트 폴더에서 `sudo docker compose logs --tail=100 wordcalendar-api`를 확인한다.

### SSH 터미널 접속

시놀로지에는 DSM 화면에 내장된 터미널 창이 따로 있는 게 아니라, DSM에서 SSH를 켠 다음 PC의 터미널로 접속한다. `제어판 > 터미널 및 SNMP > 터미널 > SSH 서비스 활성화`에서 켜고, Windows PowerShell에서 다음처럼 접속한다. `NAS_IP`는 DSM에서 확인한 내부 IP, 계정은 DSM 관리자 그룹 계정이다.

```powershell
ssh DSM관리자계정@NAS_IP
```

비밀번호를 입력하면 NAS 명령줄이 열린다. Docker 명령은 관리자 권한이 필요한 경우 앞에 `sudo`를 붙인다. 예: `sudo docker compose logs --tail=100 wordcalendar-api`. `exit`로 접속을 끝낸다. SSH는 LAN 또는 VPN에서만 허용하고 공유기에서 SSH 포트를 포워딩하지 않는다. 원격 터미널이 필요하지 않을 때 SSH 서비스를 끄면 공격 표면을 줄일 수 있다. 단계는 [Synology SSH 안내](https://kb.synology.com/ko-kr/DSM/tutorial/How_to_login_to_DSM_with_root_permission_via_SSH_Telnet)를 참고한다.

실행 중인 Python 컨테이너 안에 들어가야 할 때는 프로젝트 폴더(`/volume1/docker/wordcalendar`)에서 `sudo docker compose exec wordcalendar-api sh`를 실행한다. 컨테이너 안에서는 `python -V`로 버전을 확인하고 `exit`로 나온다. 서버는 컨테이너 시작 시 이미 자동 실행되므로 컨테이너 안에서 `python nas_api.py`를 또 실행하지 않는다. Container Manager의 프로젝트 화면에서 로그와 시작/중지 상태도 확인할 수 있다.

## 5. 네트워크와 방화벽

기본 권장: 공유기에서 앱/NAS용 **포트 포워딩을 만들지 않는다.** 처음 설치할 때 DSM 보안을 다음 순서로 설정한다.

1. DSM과 패키지를 최신 안정 버전으로 업데이트하고 `Security Advisor` 전체 검사를 실행해 권고 항목을 확인한다.
2. `제어판 > 사용자 및 그룹`에서 관리자 권한이 있는 개인 계정을 만든다. 강한 고유 암호와 MFA(DSM 7: `DSM 우측 상단 계정 메뉴 > 개인 > 계정 > 2단계 인증`)를 설정한다. 새 계정으로 DSM 로그인과 관리 작업이 가능한지 다른 브라우저에서 확인한 뒤 기본 `admin` 계정을 비활성화한다. `guest`는 비활성 상태인지 확인한다.
3. `제어판 > 보안 > 보호`에서 자동 차단과 계정 보호를 켠다. 관리자 계정으로 로그인 실패 제한을 시험하고, 정상 LAN/VPN 기기가 차단되지 않았는지 확인한다.
4. `제어판 > 보안 > 방화벽`을 켤 때는 규칙을 만들기 전에 현재 접속 LAN 대역에서 DSM 관리 접속을 허용하는 규칙을 둔다. Tailscale 네트워크로 DSM을 관리할 경우 DSM/Tailscale 공식 안내에서 필요한 인터페이스와 소스 주소를 확인해 별도 허용한다. 그 다음 불필요한 인바운드를 거부한다. 규칙 우선순위와 다른 기기에서의 재접속을 확인한 후 현재 세션을 닫는다. 방화벽에서 `100.64.0.0/10` 전체를 무조건 열지 않는다.
5. 포트 포워딩이 없고 외부에서 `NAS 공인 IP:5000`, `:5001`, `:22`, `:8787`, `:445`로 접속되지 않는지 확인한다. SMB와 SSH는 LAN/VPN에서만 사용한다. SSH는 파일 배치/compose CLI가 필요할 때만 잠깐 켜고 마친 뒤 끈다.
6. 정전 대응용 UPS를 연결하고 DSM의 UPS 지원 및 이메일/푸시 알림을 설정한다. `저장소 관리자`에서 저장소/디스크 상태 알림과 용량 경고(예: 80%)를 켠다.

NAS와 휴대폰에 Tailscale을 설치하고 같은 tailnet에 로그인한다. Tailscale 관리자 콘솔에서 기기 접근 규칙을 NAS와 허용된 휴대폰으로 제한하고, MagicDNS 및 HTTPS 인증서를 사용할 수 있게 한다. NAS SSH에서 다음 명령을 실행해 로컬 API를 tailnet 안의 HTTPS 주소로 제공한다. `tailscale serve status`에 표시된 `https://NAS이름.도메인.ts.net`을 앱의 URL로 사용한다. `Funnel`은 켜지 않는다. 현재 Tailscale CLI 공식 문법의 `--bg`는 재부팅 후에도 Serve 설정을 유지한다. NAS 패키지의 CLI 경로가 다르면 공식 Synology 통합 안내를 확인한다.

```sh
sudo /var/packages/Tailscale/target/bin/tailscale serve --bg http://127.0.0.1:8787
sudo /var/packages/Tailscale/target/bin/tailscale serve status
```

DSM 방화벽은 규칙 목록 위에서부터 일치하는 허용/거부 규칙을 적용하므로 실제 LAN/VPN 대역을 먼저 허용하고 다른 기기에서 재접속을 확인한다. Docker 포트 바인딩은 `127.0.0.1:8787`이므로 DSM API 포트 `8787`을 외부 인터페이스에 열 필요가 없다. DSM 관리 접속은 LAN/Tailscale에만 허용하고 SMB도 LAN/VPN에만 허용한다. Tailscale을 Synology TUN 모드로 설정하는 절차는 설치 방식에 따라 다르므로, Tailscale 공식 안내의 해당 설치 경로를 따른다. `admin` 비활성화, 개인 관리자 MFA, 자동 차단/계정 보호 및 Security Advisor 점검은 계정 보안 설정이다. DSM/패키지 자동 업데이트는 업무 중단 가능성을 고려해 유지보수 시간과 알림을 정해 관리한다.

공용 인터넷으로 제공해야 한다면 먼저 **사용자별 인증과 Q&A 접근 제어**를 추가해야 한다. 현재 사용자 토큰은 APK에서 추출 가능하고 `/api/qna`가 최근 질문 최대 50건을 반환하므로, HTTPS 역방향 프록시와 포트 포워딩만으로는 공개 서비스에 적합하지 않다. 이후 사용자 인증을 구현한 경우에는 DSM `제어판 > 로그인 포털 > 고급 > 역방향 프록시`에서 별도 앱 도메인 HTTPS 443 → `127.0.0.1:8787`을 만들고 도메인 인증서를 지정한다. 공유기에는 TCP 443만 NAS로 전달하며 HTTP 80은 인증서 발급 방식에 필요한 경우에만 임시 허용한다. DSM 5000/5001, SSH 22, API 8787, SMB 445는 포워딩하지 않는다. CGNAT/이중 NAT라면 단순 포트 포워딩은 작동하지 않으므로 VPN을 사용한다.

## 6. 앱 빌드와 확인

앱은 빌드할 때 연결할 백엔드가 정해진다. `WORDCALENDAR_BACKEND`를 지정하지 않으면 Firebase 빌드가 된다. Firebase 프로젝트 설정은 `android/app/google-services.json` 및 `lib/firebase_options.dart`를 사용한다.

### 새 Firebase 프로젝트 만들기와 앱 연결

먼저 데이터 저장 방식을 정한다.

- **NAS 데이터 + Firebase 푸시:** PDF/Q&A/설정은 NAS에 저장한다. Firebase는 FCM, NAS 푸시 중계 Cloud Function, 기기 토큰 목록에만 쓴다. 이 저장소의 NAS FCM 중계는 Firebase Cloud Functions를 쓰므로 결제 계정을 연결한 Blaze 요금제가 필요하다.
- **Firebase 데이터 + Firebase 푸시:** Firestore에 Q&A/설정/통계를 저장하고 Cloud Storage에 PDF를 저장한다. 이 저장소의 Firebase PDF 교체 기능에 Cloud Storage가 필요하며, 새 Firebase Storage 버킷 사용에도 Blaze 요금제가 필요하다. Cloud Functions도 Blaze가 필요하다. Blaze는 사용량에 따른 결제이므로 Google Cloud에서 예산 알림을 설정하고 사용량을 확인한다. 예산 알림은 자동 지출 차단 장치가 아니다.

#### 1) 프로젝트와 앱 ID 정하기

1. [Firebase Console](https://console.firebase.google.com/)에서 `프로젝트 추가`를 누르고 새 프로젝트를 만든다. Google Analytics는 선택 사항이다. 프로젝트 ID는 생성 후 바꾸기 어렵기 때문에 용도를 알아볼 수 있게 정한다.
2. Firebase Console의 프로젝트 설정에서 앱을 등록한다. Android `applicationId`와 iOS Bundle ID는 모두 `com.happychurch.thewordcalendar`다. Android 패키지명은 대소문자까지 정확히 일치해야 하고 Firebase에 앱을 등록한 뒤에는 새 Android 앱으로 추가해야 한다. Android 앱을 등록한 뒤 내려받은 `google-services.json`으로 `android/app/google-services.json`을 교체하고 FlutterFire 설정도 갱신한다. iOS는 `ios/Runner/GoogleService-Info.plist`와 Xcode Runner Bundle ID가 Firebase 등록 정보와 일치해야 한다.
3. iPhone도 배포할 경우 Apple Developer에서 실제 앱 Bundle ID를 등록하고 그 ID를 Xcode Runner target에도 적용한다. Apple Developer 계정 없이 iOS용 APNs 푸시 설정을 완료할 수 없다.

#### 2) Windows PC에서 FlutterFire 연결

Node.js/npm, Flutter SDK, Android Studio가 설치된 PC에서 PowerShell을 연다. Firebase CLI와 FlutterFire CLI를 한 번 설치하고 로그인한다.

```powershell
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
cd D:\my_portfolio\Date-Pdf
firebase projects:list
flutterfire configure --project=여기에_새_Firebase_프로젝트_ID
```

플랫폼 선택 화면에서 사용하는 플랫폼(Android, iOS)을 고른다. 등록 앱이 없으면 CLI가 만들도록 진행한다. CLI는 `lib/firebase_options.dart`, Firebase 연결 정보와 `firebase.json`을 갱신한다. Android 설정 파일 `android/app/google-services.json`이 새 프로젝트의 값인지 확인한다. iOS의 경우 `GoogleService-Info.plist`가 `ios/Runner/`에 있는지 확인하고, 없으면 Firebase Console에서 iOS 앱의 plist를 내려받아 그 위치에 넣는다. `firebase_options.dart` 안의 Project ID와 앱 ID가 새 Firebase 프로젝트 값인지 확인한다. 이 파일들을 예전 프로젝트 값으로 남겨두면 새 프로젝트에 연결되지 않는다.

Functions를 새 프로젝트에 배포하려면 저장소 루트에서 프로젝트 별칭도 지정한다.

```powershell
firebase use --add
```

대화형 목록에서 새 프로젝트를 선택하고 `default` 같은 별칭을 지정한다. `firebase use` 출력이 새 프로젝트 ID인지 확인한다. 같은 소스에서 여러 Firebase 프로젝트를 다룰 때는 배포 전에 현재 선택 프로젝트를 반드시 확인한다.

#### 3) Firebase 서비스 설정

1. Firebase Console의 `Firestore Database > 데이터베이스 만들기`에서 데이터베이스를 만든다. NAS 푸시 전용으로 쓸 때도 FCM 기기 토큰을 저장할 Firestore가 필요하다. 위치는 사용자와 NAS/Functions에 가까운 곳으로 정한다. 생성 후 `Rules` 탭에 저장소의 `firestore.nas.rules` 내용을 붙여 넣고 게시한다. 이 규칙은 NAS 푸시 전용이며, 앱의 Firestore 데이터 접근은 전부 차단한다.
2. Firebase Console의 `Authentication > Sign-in method`에서 `Anonymous` 로그인을 사용 설정한다. NAS 모드 앱은 알림 토큰을 기기에 연결하기 위해 익명 Firebase 로그인을 자동 수행한다. 사용자가 별도 계정을 만들거나 토큰을 직접 입력하지 않는다. 앱을 처음 실행하고 알림 권한을 허용하면 FCM 토큰이 `notification_tokens`에 기록된다. 익명 사용자는 앱 데이터 로그인 용도가 아니라 이 토큰을 해당 기기의 UID에 묶는 용도다.
3. NAS에서 백그라운드 푸시를 받을 계획이면 `functions/.env.example`을 `functions/.env`로 복사해 `NAS_PUSH_SECRET`을 설정하고, 같은 값을 NAS `.env`의 `WORDCALENDAR_NAS_PUSH_SECRET`에 둔다. `firebase deploy --only functions`를 실행해 `notifyNasEvent` 포함 Functions를 배포하고, 출력된 HTTPS URL을 NAS `.env`의 `WORDCALENDAR_NAS_PUSH_URL`에 넣는다. NAS 코드/요구사항 파일을 복사하고 `sudo docker compose up -d --build`로 재빌드한다. SMTP 값은 관리자 이메일 알림을 쓸 때만 입력한다.
4. **Firebase를 데이터 백엔드로 쓸 때만:** `Storage > 시작하기`에서 기본 버킷을 만든다. 새 프로젝트의 버킷 이름은 보통 `<프로젝트ID>.firebasestorage.app` 형식이며, `flutterfire configure` 후 `firebase_options.dart`에 새 버킷이 반영됐는지 확인한다. 이 앱은 Storage 파일 `365일 매일묵상말씀.pdf`와 Firestore 문서 `pdf_documents/current`, `pdf_catalog/current`, `pdf_settings/config`, `qna`, `page_stats`를 사용한다.

**보안 주의:** Firestore/Storage를 테스트 모드 규칙으로 공개하지 않는다. NAS 데이터 모드에서는 `firestore.nas.rules`만 사용한다. 이 규칙은 익명 인증된 기기가 자기 UID에 연결된 NAS용 알림 토큰만 쓰도록 허용하고 나머지 Firestore 읽기/쓰기는 거부한다. 따라서 이 규칙을 Firebase 데이터 모드에 적용하면 앱의 Q&A/설정/통계 읽기와 쓰기가 모두 막힌다. Firebase 데이터 모드에는 별도의 사용자 인증, 관리자 권한, Firestore/Storage 규칙이 필요하다. 현재 Firebase 기본 앱의 관리자 코드 `123456`은 서버 인증이 아니며, 공개 배포용 관리자 보안으로 사용할 수 없다.

#### 4) iPhone FCM 설정

Firebase Console에 iOS 앱을 등록한 것만으로 APNs 설정이 끝나지는 않는다. Apple Developer에서 해당 App ID에 Push Notifications를 켜고 APNs 인증 키(.p8)를 만든다. Xcode에서 Runner의 `Push Notifications`와 `Background Modes > Remote notifications`를 활성화하고, APNs 키와 Key ID, Team ID를 Firebase Console `Project settings > Cloud Messaging`에 한 번 업로드한다. 이 설정은 앱 운영자가 한 번 하면 되고, 각 iPhone 사용자가 토큰을 등록하지 않는다. 사용자는 앱을 열어 알림 권한을 허용하면 된다. Firebase Flutter 설정 과정과 Apple 푸시 요구사항은 [FlutterFire 설정 안내](https://firebase.google.com/docs/flutter/setup), [FCM Flutter 시작 안내](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)를 참고한다.

#### 5) 새 설정으로 빌드하고 확인

새 프로젝트에 연결한 다음 앱을 다시 빌드한다. NAS 빌드라면 아래 NAS 빌드 명령도 새 `firebase_options.dart`와 Android/iOS Firebase 설정 파일을 사용한다.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

먼저 실제 휴대폰에 설치하고 앱을 한 번 열어 알림 권한을 허용한다. Firebase Console Firestore에서 `notification_tokens` 문서가 자동 생성되는지 확인한 뒤 Functions 로그와 실제 PDF 업데이트/Q&A 답변으로 푸시를 검증한다. Firebase Cloud Functions는 배포 시 Blaze 요금제가 필요하므로 [Cloud Functions 배포 안내](https://firebase.google.com/docs/functions/manage-functions)와 Firebase 사용량/예산 알림을 확인한다.

### Firebase 앱 빌드

PC에서 프로젝트 폴더의 PowerShell을 열고 실행한다.

```powershell
cd D:\my_portfolio\Date-Pdf
flutter pub get
flutter build apk --release
```

결과물은 `build\app\outputs\flutter-apk\app-release.apk`이다. 직접 설치해 테스트할 때는 이 APK를 휴대폰으로 복사해 설치한다. NAS용 APK도 같은 경로와 파일명을 쓰므로 빌드 직후 결과물을 `wordcalendar-firebase.apk`처럼 다른 이름으로 복사해 보관한다. 현재 Android release 서명 설정은 개발용 debug 키를 사용한다. Play 스토어 배포 전에는 개인 release keystore와 서명을 별도로 설정해야 한다.

### iPhone 푸시 알림의 최초 설정

사용자가 각자 Firebase 콘솔에 토큰을 입력하는 방식이 아니다. 앱은 알림 권한을 요청하고, APNs 연결이 준비되면 FCM 기기 토큰을 자동으로 받아 `notification_tokens`에 등록한다. 토큰이 바뀌어도 앱의 토큰 갱신 감지기가 새 토큰을 자동 등록한다. 사용자가 해야 하는 일은 iPhone에서 앱 알림을 허용하는 것뿐이다.

단, 앱 개발자가 Apple/Firebase에서 앱 전체에 대해 한 번 설정해야 한다. 현재 Firebase iOS 앱 Bundle ID는 `com.happychurch.thewordcalendar`이며 `GoogleService-Info.plist`는 `ios/Runner/`에 있다. Apple Developer의 해당 App ID에 Push Notifications를 켜고, Xcode의 Runner target에서 **Push Notifications**와 **Background Modes > Remote notifications**를 활성화한다. Apple Developer에서 APNs 인증 키를 만들어 Firebase Console의 `Project settings > Cloud Messaging`에 업로드한다. 저장소에는 현재 iOS `Podfile`이 없고 APNs capability도 아직 설정되어 있지 않으므로, macOS/Xcode에서 iOS 빌드 구성을 마쳐야 iPhone 앱과 푸시를 검증할 수 있다. NAS용 FCM 중계를 쓰려면 위 설정과 NAS 푸시 중계 절차를 모두 마친다.

### NAS 앱 빌드

1. NAS를 Tailscale에 연결하고 `tailscale serve status`에 나온 HTTPS 주소를 복사한다. 예: `https://wordcalendar-nas.example.ts.net`. 주소 끝에 `/wordcalendar`를 붙이지 않는다.
2. 주소를 실제 Tailscale HTTPS 주소로 바꾸고 PC PowerShell에서 아래 명령을 실행한다. 사용자 토큰은 NAS `.env`의 `WORDCALENDAR_NAS_TOKEN`과 동일한 값이어야 한다. `Read-Host` 입력은 화면에 표시되지 않고 토큰 자체는 PowerShell 명령 기록에 남지 않는다. 빌드 인자와 결과 APK에는 토큰이 포함되므로 APK를 신뢰할 수 있는 사람에게만 배포한다.

```powershell
cd D:\my_portfolio\Date-Pdf
flutter pub get
$SecureUserToken = Read-Host "NAS 사용자 토큰 입력" -AsSecureString
$WordCalendarUserToken = [System.Net.NetworkCredential]::new("", $SecureUserToken).Password
flutter build apk --release --dart-define=WORDCALENDAR_BACKEND=nas --dart-define=WORDCALENDAR_NAS_BASE_URL=https://wordcalendar-nas.example.ts.net --dart-define=WORDCALENDAR_NAS_TOKEN=$WordCalendarUserToken
Remove-Variable WordCalendarUserToken, SecureUserToken
```

3. 빌드 결과를 `wordcalendar-nas.apk` 등으로 따로 복사한 뒤 휴대폰에 설치하고 Tailscale을 켠다. 관리자 기능이 필요하면 앱 설정의 관리자 모드에서 NAS `.env`에 저장한 `WORDCALENDAR_NAS_ADMIN_TOKEN`을 입력한다. 관리자 토큰은 빌드 명령에 넣지 않는다. APK에는 사용자 토큰이 포함되므로 APK를 신뢰할 수 없는 사람에게 전달하지 말고, 유출 시 새 사용자 토큰으로 NAS 설정과 APK를 함께 교체한다. Firebase 기본 빌드는 코드 `123456`을 사용하므로 Firebase를 계속 운영할 경우 별도 인증 교체가 필요하다. 설치된 앱을 Firebase/NAS 간 전환할 때는 해당 백엔드로 다시 빌드한 APK를 설치한다.

#### 배치 파일로 NAS 앱 빌드

저장소의 `deploy\synology\build_nas_apk.bat`을 실행하면 실제 Tailscale HTTPS 기본 주소(예: `https://nas-name.example.ts.net`, 끝에 앱 경로나 `/wordcalendar`를 붙이지 않음)와 NAS 사용자 토큰을 입력받아 NAS용 APK를 빌드한다. 토큰 입력은 별도의 PowerShell 보안 입력으로 화면에 표시되지 않지만, Flutter 빌드 프로세스 인자와 APK 안에는 들어간다. BAT 파일이나 결과 APK를 공개 공유하지 않는다.

```cmd
deploy\synology\build_nas_apk.bat
```

완료되면 `build\app\outputs\flutter-apk\wordcalendar-nas.apk`가 만들어진다. `app-release.apk`도 같은 NAS 설정으로 빌드된 파일이므로 Firebase용으로 착각해 배포하지 않는다. Firebase APK가 필요하면 `flutter build apk --release`를 다시 실행하고 그 결과를 별도 파일명으로 보관한다. Tailscale이 켜진 휴대폰에 NAS APK를 설치해 접속을 확인한다.

앱에서 날짜 선택/PDF 다운로드/오프라인 캐시, 제목 표시, 조회수, Q&A 질문과 관리자 답변·삭제, 일반 사용자 화면에서 작성자 이름 숨김, PDF 교체, 제목 카탈로그 저장을 확인한다. 서버 `/api/pdf/current/metadata`는 PDF 파일 정보와 페이지 수를 제공한다. 제목 자동 분석은 **Python API가 수행하지 않는다**. 관리자 앱의 `제목 카탈로그` 화면이 PDF를 읽고 OCR/레이아웃 분석 후 결과를 NAS 카탈로그에 저장한다. 실제 PDF로 365개 중 성공·저신뢰·실패 개수를 확인하고 낮은 신뢰도는 사람이 검수한다. PDF를 교체한 뒤에는 새 PDF 기준으로 제목 카탈로그도 다시 분석/검수한다.

### Windows BAT로 AI 제목 추출과 검수

저장소의 `python` 폴더에는 PDF 제목을 AI로 추출하고 검수용 HTML을 만드는 선택적 도구도 있다. NAS 서버를 시작하는 BAT와는 별도 기능이다. OpenAI API 사용량에 따라 비용이 발생할 수 있으니 세 날짜 시험을 먼저 실행하고 결과/사용량을 확인한다.

1. `python\01_setup.bat`을 더블클릭한다. 이 파일은 `python\.venv` 가상환경을 만들고 `requirements.txt`를 설치한 뒤 `.env.example`을 `python\.env`로 복사한다. 설치 후 메모장에서 `python\.env`를 열어 `OPENAI_API_KEY`를 입력하고 저장한다. API 키는 공유하거나 Git에 올리지 않는다.
2. PDF `365일 매일묵상말씀.pdf`를 `python` 폴더에 넣고 `python\02_test_3_titles.bat`을 먼저 실행한다. 지정된 2026년 9월 13일, 9월 23일, 10월 27일 제목 3개만 시험한다. 입력 파일명이나 연도가 다르면 BAT의 `--pdf`, `--year`, `--only` 값을 편집한다.
3. 3개 결과와 비용을 확인한 후 전체가 필요할 때 `python\03_extract_all.bat`을 실행한다. 기본은 2026년 365일, 동시 요청 3개이며 결과는 `python\output\titles.json`에 저장된다. 저신뢰 항목은 fallback 모델로 추가 요청될 수 있다.
4. `python\04_build_review.bat`을 실행하면 `python\output\review.html`이 브라우저에서 열린다. 제목과 PDF 이미지 크롭을 검수하고 `수정 JSON 다운로드`를 누른다. 앱 관리자 화면의 `말씀 제목 카탈로그 > JSON 제목 파일 불러오기`에서 내려받은 JSON을 선택해 NAS/Firebase 카탈로그로 저장한다.

각 BAT는 현재 위치와 상관없이 스크립트가 있는 폴더를 기준으로 실행된다. `01_setup.bat`은 가상환경을 다시 만들지 않고 기존 `.venv`를 재사용한다. PDF OCR 결과는 반드시 사람이 확인하며, PDF의 날짜/페이지 배열이 기본 가정(2026년, 첫 묵상 PDF 페이지 4쪽)과 다르면 전체 추출 전에 스크립트 인자를 조정한다.

### PDF 및 Q&A 알림 동작

알림은 휴대폰의 OS 알림 권한과 앱 설정의 PDF/Q&A 알림 스위치가 모두 켜져 있어야 보인다. 앱은 알림을 높은 중요도의 로컬 알림 채널에 표시한다.

| 백엔드 | PDF 업데이트 | 내 질문에 답변 | 백그라운드/앱 종료 |
| --- | --- | --- | --- |
| Firebase | 앱이 열려 있으면 Firestore 변경을 감지한다. 배포된 `functions/index.js`의 `notifyOnPdfUpdate`가 등록된 FCM 기기들에도 푸시를 보낸다. | Firestore 변경 감지와 `notifyOnQnaAnswer` FCM 푸시를 쓴다. 질문 작성 시 저장한 해당 기기의 토큰으로만 보낸다. | Cloud Functions가 배포되어 있고 FCM/OS 알림 권한이 정상이라면 푸시 수신이 가능하다. 앱이 열려 있을 때는 앱이 로컬 알림으로 표시한다. 실제 기기별 수신은 배포/FCM 설정 후 확인해야 한다. |
| NAS | 기본은 앱 실행 중 30초 간격 확인과 로컬 시스템 알림이다. FCM 중계를 설정하면 NAS가 Cloud Function을 호출해 등록된 NAS 앱 기기에 푸시한다. | 기본은 앱 실행 중 30초 간격 확인이다. FCM 중계를 설정하면 답변된 질문을 쓴 기기에 푸시한다. | FCM 중계와 Functions 배포가 완료되면 Firebase 경로로 휴대폰 푸시를 받을 수 있다. 미설정/실패 시 앱이 열려 있는 동안의 30초 확인이 대체 경로다. |

알림 문구는 PDF의 경우 “PDF가 업데이트되었습니다 / 새로운 말씀 PDF를 확인해 보세요”, 답변의 경우 “Q&A 답변이 등록되었습니다”와 답변 일부(최대 80자)다. NAS에서도 앱을 닫은 뒤 휴대폰 푸시를 받으려면 다음 FCM 중계를 한 번 설정한다.

1. `functions/.env.example`을 `functions/.env`로 복사하고 `NAS_PUSH_SECRET`에 BAT에서 만든 중계 비밀값을 입력한다. 이 파일은 Git에 올리지 않는다.
2. NAS `/volume1/docker/wordcalendar/.env`에 같은 값을 `WORDCALENDAR_NAS_PUSH_SECRET`으로 넣는다. `WORDCALENDAR_NAS_PUSH_URL`은 비워두지 말고, Firebase Functions 배포가 출력한 `notifyNasEvent` HTTPS 주소를 넣는다.
3. 저장소 루트에서 `firebase deploy --only functions`를 실행하고, 출력된 `notifyNasEvent` URL을 NAS `.env`의 `WORDCALENDAR_NAS_PUSH_URL`에 설정한다. 갱신된 `python/nas_api.py`와 `python/nas_requirements.txt`를 NAS `/volume1/docker/wordcalendar/app/`에 복사하고 프로젝트 경로에서 `sudo docker compose up -d --build`를 실행한다. NAS 앱도 NAS URL/사용자 토큰으로 다시 빌드해 설치한다. NAS APK는 FCM을 위해 기존 Firebase 프로젝트 설정을 사용하지만, Q&A/PDF 데이터는 NAS에 둔다.
4. Firebase Firestore의 `notification_tokens`에 기기의 FCM 토큰이 등록되는지 확인한다. `firestore.nas.rules`는 익명 인증 UID와 문서의 `deviceId`가 일치하는 경우에만 NAS용 토큰 등록/갱신을 허용한다. 앱을 처음 실행하고 알림 권한을 허용하면 등록된다. NAS 관리자 모드에서 PDF 교체 또는 Q&A 답변을 시험하고, 앱이 백그라운드/종료 상태일 때 푸시가 오는지 확인한다. iPhone에서는 APNs 키와 Xcode capability 설정도 필요하다.

Firebase 앱의 백그라운드/종료 푸시도 같은 Cloud Functions에 의존한다. Q&A 새 질문에 대한 관리자 이메일은 `functions/.env`에 SMTP와 수신 주소를 설정한 경우에만 전송된다. 상세 설정은 `functions/README.md`를 따른다. 푸시가 오지 않으면 NAS 로그의 `NAS push relay failed`, Firebase Functions 로그, 알림 권한과 토큰 등록을 확인한다. 중계 미설정 시 NAS 앱이 열려 있을 때의 30초 확인만 동작한다.

### PDF 교체 후 사용자 모드로 돌아가기

관리자가 `관리자 모드 진입 → PDF 교체 → 관리자 모드 해제` 순서로 작업해도 알림은 **PDF 교체가 서버에 반영될 때** 발생하며, 관리자 모드 해제 때 새로 발생하지 않는다. 관리자 기기도 알림 대상에 포함된다. 따라서 PDF 알림 설정과 OS 권한이 켜져 있으면 관리자 화면을 보고 있는 동안 알림이 오거나, 전달이 지연되면 관리자 모드 해제 뒤에 도착할 수 있다. 모드 해제는 이미 발생한 알림을 취소하지 않는다. 관리자가 자기 기기에서 알림을 받지 않으려면 해당 기기의 PDF 알림 설정을 끄면 된다. NAS 모드는 푸시 중계를 설정하지 않았다면 앱이 열려 있을 때 30초 간격으로 변경을 확인한다. PDF 교체 직후 관리자 기기는 캐시를 새로 받으며, 다른 온라인 기기도 푸시 또는 앱 실행 중 변경 확인을 통해 새 PDF를 받는다. 오프라인 기기는 기존 캐시를 읽다가 다시 연결되면 서버의 최신 PDF를 확인한다. PDF 내용이나 페이지 구성이 달라졌으면 제목 카탈로그 분석은 별도로 다시 실행하고 결과를 검수한다. NAS 관리자 모드 종료는 관리자 토큰을 앱 메모리에서 지우며 PDF 파일 자체에는 영향을 주지 않는다.

## Q&A 작성자 표시와 질문 삭제

질문 작성 시 `닉네임` 또는 `익명`을 고른다. 닉네임을 고르면 현재 앱에 저장된 닉네임을 관리자에게 표시하고, 익명을 고르면 작성자 표시는 `익명`으로 저장한다. 일반 사용자의 Q&A 목록과 상세 화면에는 어느 경우에도 작성자 이름을 표시하지 않는다. NAS 모드의 `GET /api/qna` 응답에서도 `authorName`과 FCM 알림 토큰을 제외한다. 작성자 이름을 포함한 관리 목록은 `GET /api/admin/qna`로 분리되어 관리자 토큰이 필요하다. 알림 대상 기기를 구분하기 위한 불투명한 기기 ID는 NAS의 foreground 알림 확인에 사용한다.

관리자 Q&A 화면에서 질문을 열고 `질문 삭제`를 선택하면 확인창을 거쳐 NAS 데이터베이스에서 삭제한다. 삭제와 답변 수정은 관리자 토큰이 있어야 하며 오프라인에서는 사용할 수 없다. 삭제한 항목 복구는 설정된 Hyper Backup 백업에서 수행한다. NAS가 아닌 기존 Firebase 백엔드를 쓰는 경우 앱 화면에서는 작성자를 감추지만, Firestore 문서 접근 자체의 비공개 여부는 Firebase Security Rules 설정에 달려 있다.

## 오프라인 모드

NAS 백엔드 빌드에서는 앱이 NAS API 연결 상태를 확인하고, 연결이 끊기면 화면 상단에 오프라인 안내를 표시한다. PDF, PDF 제목/목록, 설정, 그리고 기기에서 마지막으로 받아 둔 Q&A는 캐시가 있는 범위에서 열람할 수 있다. 캐시는 기기 내부에 저장되므로 앱 데이터 삭제나 앱 재설치, 다른 기기에서는 기존 캐시를 사용할 수 없다.

오프라인에서는 Q&A 질문 등록, 관리자 답변 저장, 읽음 상태 변경을 할 수 없다. 입력 내용을 오프라인 대기열에 넣지 않으며, 재연결 후 자동으로 전송하지 않는다. 따라서 앱이 등록 성공으로 잘못 안내하거나 예전 오프라인 입력이 나중에 뜻하지 않게 서버로 올라가지 않는다. 연결이 회복되면 Q&A 목록은 화면이 활성화된 동안 약 30초 간격으로 다시 받아오며, 질문/답변 버튼이 활성화된다. 질문·답변 저장 도중 연결이 끊긴 경우 오류 안내가 나오고, 저장 여부가 확인되지 않았다면 서버 목록을 새로고침해 중복 제출을 피한다.

NAS API가 응답하면(인증 오류 포함) NAS 연결 자체는 가능한 것으로 판단한다. 잘못된 주소/토큰, 방화벽 차단, NAS 종료처럼 요청에 응답이 오지 않는 경우를 오프라인으로 표시한다. 앱의 백그라운드에서는 운영체제가 주기 확인을 늦추거나 멈출 수 있으므로, 알림/실시간 동기화 보장은 별도 푸시 서비스가 필요하다.

## 7. 백업·복구·운영

`Hyper Backup > + > 데이터 백업 작업 > 로컬 폴더 및 USB`에서 원본 `wordcalendar-data`와 필요한 DSM 설정을 선택하고 대상 `/volume2/wordcalendar-backup`을 고른다. 다중 버전, 일일 백업, 보존 정책(예: 30개), 주간 무결성 검사를 설정한다. SQLite WAL 사용 중이므로 파일을 임의로 `cp`하는 대신 Hyper Backup의 파일 백업 또는 API 정지 후 복사/복구를 사용한다. 별도로 주 1회 이상 외장 디스크/원격 NAS/클라우드로 보내고 한 번은 실제 복원 테스트를 한다. API는 PDF 교체 전 사본 최근 20개, JSON별 최근 30개를 `/volume1/wordcalendar-data/backups`에 보관한다. 같은 풀이라 재해 대비 백업은 아니다. 디스크 SMART 오류, 저장소 풀 성능 저하, 백업 실패, 용량 80% 접근 알림을 DSM에서 켠다.

복구 시 새 볼륨에 공유 폴더를 만든 뒤 Hyper Backup에서 `wordcalendar-data`를 복원한다. 컨테이너를 중지한 상태에서 복원하고, 데이터 폴더·권한·`.env`를 확인한 뒤 다시 시작한다. `.env`는 백업에 무조건 포함하지 말고 비밀번호 관리자에 두 토큰을 별도로 보관한다. 토큰이 노출되면 `.env` 값을 바꾸고 컨테이너를 재시작한 뒤 앱도 새 사용자 토큰으로 다시 빌드한다.

## 로컬 검증과 현재 한계

### 2026-10-06 재점검

- `flutter analyze --no-pub`, `flutter test`, `python -m pytest python/test_nas_api.py -q` 통과. NAS API 테스트는 잘못된 PDF 업로드가 기존 PDF를 보존하는지, FCM 중계 장애 중에도 Q&A 답변 저장이 완료되는지, 통계 중복 요청이 한 번만 집계되는지 확인한다.
- 임시 데이터 폴더로 NAS API를 실제 Uvicorn 프로세스로 띄워 인증, 빈 NAS의 PDF 404, PDF 업로드/다운로드, Q&A 권한, 중복 조회 집계를 확인했다. PDF 메타데이터에서 실제 페이지 수를 앱이 읽는 `pdfPageCount` 키로 제공하지 않던 불일치를 수정했다.
- Android 17(API 37) Pixel 에뮬레이터에서 NAS 릴리스 APK를 설치해 실행했다. 홈 화면, PDF 열기, Q&A 화면, Android 알림 권한 요청을 확인했다. NAS 연결을 끊으면 오프라인 배너가 표시되고 Q&A 작성이 비활성화되며, 캐시 PDF를 계속 읽을 수 있었다.
- 빌드 APK는 `minSdk 24`(Android 7.0), `targetSdk 36`이고 `arm64-v8a`, `armeabi-v7a`, `x86_64`를 포함한다. 파일 크기는 약 108 MiB다. 이 수치는 패키지 설정으로 판단한 지원 범위이며 실제 휴대폰별 성능/화면 검증은 아니다.
- 이 실행 환경의 Docker가 없어 Synology Container Manager와 compose 배포는 실제 구동하지 못했다. 로컬 Python API 검증은 저장소의 NAS API를 임시 폴더에서 실행한 모의 환경이며 NAS DSM 권한, reverse proxy/Tailscale, 디스크 장애 복구까지 검증한 것은 아니다.
- 테스트용 Firebase 설정에서 익명 인증 요청이 `CONFIGURATION_NOT_FOUND`로 거부됐다. 앱은 종료되지 않고 NAS API와 오프라인 캐시로 계속 실행됐지만, 이 프로젝트 설정으로는 FCM 토큰 등록과 실제 푸시를 확인하지 못했다. 새 Firebase 프로젝트에 익명 인증, Firestore 규칙, Android 앱 ID를 올바르게 설정한 뒤 실제 기기에서 PDF/Q&A 푸시를 다시 확인해야 한다.
- 이 저장소에는 iOS `GoogleService-Info.plist`와 Bundle ID 설정이 있지만 `Podfile` 및 Push Notifications/APNs 연결은 아직 구성되지 않았다. Xcode가 없는 Windows 환경이라 iOS 빌드 및 iPhone 푸시는 확인하지 못했다. 프로젝트의 iOS 최소 버전은 15.0이다.
- 테스트 PDF는 빈 페이지 368장으로 제목 OCR 검증 자료가 아니다. 실제 365일 PDF로 제목 자동 추출 정확도와 저신뢰 결과를 확인해야 한다. Android 빌드에서는 Firebase 플러그인의 Kotlin Gradle Plugin 호환성 경고가 나왔으며 현재 빌드는 성공하지만 향후 Flutter/플러그인 업그레이드 시 재확인이 필요하다.

### 2026-10-08 새 Firebase 프로젝트와 앱 ID 확인

- Android `applicationId`와 iOS Bundle ID를 `com.happychurch.thewordcalendar`로 맞추고 새 프로젝트의 `google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`를 연결했다.
- `flutter build apk --release` 성공. Android 17(API 37) 에뮬레이터에 새 패키지 APK를 설치해 홈 화면과 Firebase 네이티브 초기화를 확인했다. 새 프로젝트에는 PDF 데이터가 없어 미리보기는 표시되지 않는다. Firestore 데이터/규칙, 익명 인증, 실제 FCM 푸시는 별도로 설정·검증해야 한다.
- Firebase 및 알림 초기화를 기다리느라 Flutter 스플래시 화면에 머물지 않도록, 앱 화면을 먼저 띄운 뒤 알림/FCM 초기화를 비동기로 시작하게 했다.
- iOS plist와 Bundle ID는 준비했지만 이 Windows 환경에는 Xcode가 없고 저장소에 iOS `Podfile`도 없어 iOS 빌드는 수행하지 못했다. APNs/Push Notifications 설정도 남아 있다.

```powershell
python -m pip install -r python/nas_requirements.txt httpx pytest
python -m pytest python/test_nas_api.py -q
flutter analyze --no-pub
flutter test
```

API 통합 테스트는 사용자/관리자 권한, 잘못된 PDF 거부, 정상 PDF 다운로드, 설정, Q&A 답변과 재시도, 조회수 중복 방지를 확인한다. 실제 Synology 장비, 실 PDF 365페이지 OCR 품질, Android 푸시 표시, VPN/방화벽 실접속은 NAS와 휴대폰에서 확인해야 한다. NAS 사용자 토큰은 APK에 포함되며 Q&A 일반 목록 API(최근 질문 최대 50건)에 접근할 수 있다. 민감한 Q&A나 불특정 사용자가 있는 서비스에는 사용자별 인증·데이터 분리가 선행돼야 한다.

### 2026-10-08 NAS/앱 재검증

- `flutter analyze --no-pub` 통과, `python -m pytest python/test_nas_api.py -q` 통과(2개). Firebase 기본 모드 APK와 NAS 모드 APK가 모두 release 빌드됐다. APK는 약 109 MiB다.
- Android 17(API 37) 에뮬레이터에 NAS 모드 release APK를 설치해 실행했다. Firebase 네이티브 초기화 후 홈 앱 프로세스가 유지됐고 종료/크래시는 없었다. 테스트 주소 `nas.example.ts.net`은 실제 NAS가 아니어서 예상대로 DNS 연결 실패 및 오프라인 PDF 로드 오류 로그가 발생했다. 이 확인은 실제 NAS 데이터 연결을 입증하지 않는다.
- `flutter test`는 제목 카탈로그 파서 테스트 2개는 통과했지만 기존 `test/widget_test.dart`의 앱 스모크 테스트가 실패했다. 테스트가 실제 `main()`을 거치지 않고 `TheWordCalendarApp`을 바로 그려 Firebase 초기화를 생략해 `FirebaseFirestore.instance`에서 `[core/no-app]`을 발생시킨다. Android 에뮬레이터 실행은 성공했지만 이 위젯 테스트 픽스처는 수정이 필요하다.
- 이 Windows 환경에는 Docker CLI가 없고 실제 Synology 장비도 연결되지 않았다. 그러므로 Container Manager 프로젝트 생성, DSM 공유 폴더 ACL, 디스크 SMART/스크러빙, Tailscale Serve와 외부 모바일 네트워크 연결, 실제 PDF/Q&A 데이터 기능과 푸시 알림은 검증하지 못했다. NAS 설치 뒤 이 README의 API 확인 및 앱 기능 체크리스트를 실제 장비와 휴대폰에서 실행한다.
- `deploy_to_nas.bat`과 `build_nas_apk.bat`의 안내와 파일 경로를 점검했지만, NAS 전송·Compose 실행은 실제 장비가 없어 원격 실행 검증을 하지 못했다. 사용 전에 NAS에 `.env`, 공유 폴더와 SSH 접근을 준비한다.

참고: [DS1825+ 사양](https://www.synology.com/en-global/products/DS1825%2B), [DSM 저장소 풀 생성](https://kb.synology.com/en-id/DSM/help/DSM/StorageManager/storage_pool_create_storage_pool?version=7), [Container Manager 프로젝트](https://kb.synology.com/tr-tr/DSM/help/ContainerManager/docker_project?version=7), [DSM 방화벽](https://kb.synology.com/index.php/en-us/DSM/help/DSM/AdminCenter/connection_security_firewall?version=7), [Synology 백업 전략](https://kb.synology.com/en-af/DSM/tutorial/How_to_back_up_your_Synology_NAS), [Tailscale Synology](https://tailscale.com/docs/integrations/synology), [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve).

## Name change and NAS upgrade

The Flutter package, display labels, Docker Compose service, NAS APK artifact, environment variables, and database filename use `wordcalendar` / `TheWordCalendar`. Android and iOS keep the registered application ID `com.happychurch.thewordcalendar`.

Before updating an existing NAS install, stop the old Compose project and make a backup of `/volume1/wordcalendar-data`. Rename the keys in `/volume1/docker/wordcalendar/.env` to `WORDCALENDAR_NAS_TOKEN`, `WORDCALENDAR_NAS_ADMIN_TOKEN`, `WORDCALENDAR_NAS_PUSH_URL`, and `WORDCALENDAR_NAS_PUSH_SECRET`; keep each existing value unchanged. The API no longer reads `DATEPDF_*` keys. Redeploy with `deploy_to_nas.bat` or copy the updated files and run `sudo docker compose up -d --build` from `/volume1/docker/wordcalendar`.

On first startup, the API copies `data/datepdf.sqlite3` into `data/wordcalendar.sqlite3`, checks the new database, and retains the original data as `data/wordcalendar.sqlite3.pre-rename-backup`. Check the API logs and test Q&A/view counts before deleting that backup. If both database filenames already exist, the API stops with an error rather than choosing one and risking overwriting data; back up `/data` and resolve the two files manually. The shared data-folder path remains `/volume1/wordcalendar-data`.
