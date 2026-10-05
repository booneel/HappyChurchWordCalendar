# DatePDF: Synology DS1825+ 설치와 앱 연결

이 프로젝트는 날짜별 PDF 보기, 제목 카탈로그, 조회수, Q&A, 관리자 PDF 교체를 제공한다. 기본 빌드는 Firebase를 사용한다. `DATEPDF_BACKEND=nas`로 빌드하면 Flutter 앱이 `python/nas_api.py`의 FastAPI 서버에 연결한다. NAS 서버는 PDF와 JSON 파일, SQLite를 `/data`에 저장한다. 실제 DS1825+에 접속해 설치한 상태는 아니며, 아래 순서는 NAS 소유자가 DSM에서 수행해야 한다.

## 1. 디스크 계획

| 용도 | 물리 디스크 | DSM 설정 | 대략적인 사용 가능 용량 |
| --- | --- | --- | --- |
| 주 저장소 `/volume1` | 4 TB × 4 | 저장소 풀 1, SHR-1, Btrfs 볼륨 1 | 약 12 TB(표기 단위로 약 10.9 TiB, 파일 시스템 예약분 제외) |
| 보조 저장소 `/volume2` | 20 TB × 1 | 저장소 풀 2, Basic, Btrfs 볼륨 2 | 약 20 TB(약 18.2 TiB, 예약분 제외) |

4 TB 4개를 같은 풀에 넣어 1개 고장을 견디게 한다. 20 TB를 4 TB 풀에 섞지 않는다. 단일 20 TB 디스크는 고장 시 전체가 사라질 수 있으므로 `/volume2`는 *두 번째 사본*이며 유일한 보관 장소가 아니다. 랜섬웨어·도난·화재는 같은 NAS의 두 볼륨에 영향을 준다. 중요한 데이터는 별도 USB 디스크, 다른 NAS 또는 클라우드에 세 번째 사본을 둔다. 4 TB 4개에 SHR-2를 택하면 두 디스크 고장을 견디지만 용량이 약 8 TB로 준다. 현재 용도라면 SHR-1 + 보조/외부 백업이 균형이 좋다. 기존 디스크에 데이터가 있으면 풀 생성 전에 다른 장소로 백업한다. 새 풀 생성은 대상 디스크를 초기화한다.

1. DS1825+와 디스크의 정확한 모델이 [Synology 호환 목록](https://www.synology.com/en-global/compatibility?model=DS1825%2B&search_by=drives)에 있는지 확인한다. DSM/펌웨어를 최신 안정 버전으로 업데이트하고 각 디스크 SMART 상태를 확인한다.
2. DSM `저장소 관리자 > 저장소`에서 **새 저장소 풀 1**을 만든다. 4 TB 네 개만 선택, RAID 유형 `SHR (1개 디스크 보호)`를 선택한다. 이 풀에 **볼륨 1**, `Btrfs`, 가능한 용량 전체를 만든다. 풀 생성·검사·동기화 완료까지 기다린다.
3. 같은 화면에서 20 TB 한 개만 골라 **저장소 풀 2**, 유형 `Basic`, **볼륨 2** `Btrfs`를 만든다. `/volume1`과 `/volume2` 번호는 생성 순서에 따라 확인한다. 다르면 아래 경로도 실제 번호에 맞춘다.
4. `저장소 관리자 > HDD/SSD`에서 SMART 빠른 검사 일정과 정기 확장 검사를 잡고, `데이터 스크러빙`은 지원되는 풀 1에 월 1회 저사용 시간대로 설정한다. Btrfs 공유 폴더에 데이터 체크섬을 켜고, `Snapshot Replication`의 스냅샷을 예를 들어 하루 1회/30일 보관으로 설정한다. 스냅샷·RAID는 백업을 대체하지 않는다.

## 2. DSM에서 폴더와 패키지 만들기

`제어판 > 공유 폴더 > 생성`으로 아래 공유 폴더를 만든다. 관리자만 쓰기 가능하게 하고 일반 사용자/guest 권한은 없앤다. `datepdf-data`의 Btrfs 데이터 체크섬을 활성화한다. File Station에서 하위 폴더를 만든다.

```text
/volume1/docker/datepdf/            # Container Manager 프로젝트 폴더
  compose.yaml
  .env                         # NAS에서 직접 생성. Git에 올리지 않음
  app/
    Dockerfile.nas
    nas_api.py
    nas_requirements.txt
/volume1/datepdf-data/               # 공유 폴더: 서버 영구 데이터
  data/
    current.pdf                 # 최초 배포 전 Firebase에서 가져오기
    catalog.json                # 최초 이전 시 선택
    settings.json               # 최초 이전 시 선택
    qna.json                    # 최초 시작 전 이전용
    stats.json                  # 최초 시작 전 이전용
    datepdf.sqlite3             # 서버가 생성
  backups/                      # 서버가 PDF/JSON 교체 전 사본 생성
/volume2/datepdf-backup/             # Hyper Backup 대상 공유 폴더
```

공유 폴더 이름은 `docker`, `datepdf-data`, `datepdf-backup`이다. `docker`와 `datepdf-data`는 볼륨 1, `datepdf-backup`은 볼륨 2를 고른다. `data`, `backups`, `app`은 File Station 하위 폴더다. `백업` 폴더는 컨테이너에 연결하지 않는다. `패키지 센터`에서 **Container Manager**, **Hyper Backup**, **Snapshot Replication**, **Security Advisor**, 원격 접속 시 **Tailscale**을 설치한다. DS1825+에서 Container Manager 사용 가능 여부는 설치 전 DSM 패키지 센터에서 확인한다.

## 3. Firebase 데이터 이전

데이터를 이전하는 동안 기존 앱에서 PDF/제목/Q&A 변경을 잠시 중지한다. 먼저 Firebase의 Storage PDF와 Firestore `pdf_catalog/current`, `pdf_settings/config`, `pdf_documents/current`, `qna`, `page_stats`를 별도 백업한다. PC에서 Google Cloud/Firebase 서비스 계정 JSON을 안전하게 받아 다음 명령을 실행한다. 계정 파일은 프로젝트 저장소나 NAS 웹 공유 폴더에 넣지 않는다.

```powershell
cd D:\my_portfolio\Date-Pdf
python -m pip install firebase-admin
python python/export_firebase_to_nas.py --service-account C:\secure\firebase-service-account.json --bucket date-pdf.firebasestorage.app --output C:\secure\datepdf-export
```

`C:\secure\datepdf-export\data`의 파일을 File Station/SMB로 `/volume1/datepdf-data/data/`에 복사한다. **서버 첫 시작 전에** `qna.json`과 `stats.json`을 복사해야 SQLite에 자동 이관된다. 이미 서버를 시작했다면 데이터베이스를 임의로 덮어쓰지 말고 NAS 백업 후 별도 이전 절차를 잡는다. Firebase 원본은 NAS 데이터와 제목/질문/조회수를 대조하고 복원 시험을 마칠 때까지 보존한다. 서비스 계정과 복사본은 민감한 데이터이므로 접근을 제한한다.

## 4. 서버 배포

1. 이 저장소의 `deploy/synology/compose.yaml`을 NAS `/volume1/docker/datepdf/compose.yaml`로, `python/Dockerfile.nas`, `python/nas_api.py`, `python/nas_requirements.txt`를 `.../app/`으로 복사한다. 같은 폴더에 있는 `deploy/synology/env.example`을 참고해 `/volume1/docker/datepdf/.env`를 NAS에서 새로 만든다. 두 토큰은 서로 다른 32자 이상의 무작위 값이어야 한다. PC에서 각각 `python -c "import secrets; print(secrets.token_urlsafe(48))"`를 실행해 만든다. 관리자 토큰을 사용자 APK에 넣지 않는다.
2. SSH에서 `sudo chmod 600 /volume1/docker/datepdf/.env`를 실행한다. 프로젝트와 데이터 폴더는 관리자 외의 계정이 읽거나 수정하지 못하도록 DSM 공유 폴더 권한을 확인한다. 초기 PDF/JSON도 컨테이너에서 읽을 수 있어야 한다.
3. `Container Manager > 프로젝트 > 생성`에서 프로젝트명 `datepdf`, 경로 `/volume1/docker/datepdf`, `compose.yaml` 사용을 선택한다. 이미지를 빌드하고 프로젝트를 시작한다. CLI를 쓰면 해당 폴더에서 `sudo docker compose up -d --build`를 실행한다. `sudo docker compose logs --tail=100 datepdf-api`로 오류가 없는지 확인한다.
4. 호스트 포트는 `127.0.0.1:8787`에만 열린다. NAS SSH에서 아래처럼 확인한다. Windows에서는 `curl.exe`를 사용한다.

```sh
curl -i -H 'Authorization: Bearer <USER_TOKEN>' http://127.0.0.1:8787/api/settings/pdf
curl -i -H 'Authorization: Bearer <ADMIN_TOKEN>' http://127.0.0.1:8787/api/admin/check
```

둘 다 200이어야 하고 잘못된 토큰은 401 또는 403이어야 한다. 파일 교체 시 `.../app/`에 새 코드를 복사하고 `sudo docker compose up -d --build`를 다시 실행한다. **Container Manager의 프로젝트 `정리/Clean` 또는 공유 폴더 삭제는 데이터 보존을 확인하기 전 사용하지 않는다.** 컨테이너 재시작만으로 `/volume1/datepdf-data`는 유지된다.

### SSH 터미널 접속

시놀로지에는 DSM 화면에 내장된 터미널 창이 따로 있는 게 아니라, DSM에서 SSH를 켠 다음 PC의 터미널로 접속한다. `제어판 > 터미널 및 SNMP > 터미널 > SSH 서비스 활성화`에서 켜고, Windows PowerShell에서 다음처럼 접속한다. `NAS_IP`는 DSM에서 확인한 내부 IP, 계정은 DSM 관리자 그룹 계정이다.

```powershell
ssh DSM관리자계정@NAS_IP
```

비밀번호를 입력하면 NAS 명령줄이 열린다. Docker 명령은 관리자 권한이 필요한 경우 앞에 `sudo`를 붙인다. 예: `sudo docker compose logs --tail=100 datepdf-api`. `exit`로 접속을 끝낸다. SSH는 LAN 또는 VPN에서만 허용하고 공유기에서 SSH 포트를 포워딩하지 않는다. 원격 터미널이 필요하지 않을 때 SSH 서비스를 끄면 공격 표면을 줄일 수 있다. 단계는 [Synology SSH 안내](https://kb.synology.com/ko-kr/DSM/tutorial/How_to_login_to_DSM_with_root_permission_via_SSH_Telnet)를 참고한다.

실행 중인 Python 컨테이너 안에 들어가야 할 때는 프로젝트 폴더(`/volume1/docker/datepdf`)에서 `sudo docker compose exec datepdf-api sh`를 실행한다. 컨테이너 안에서는 `python -V`로 버전을 확인하고 `exit`로 나온다. 서버는 컨테이너 시작 시 이미 자동 실행되므로 컨테이너 안에서 `python nas_api.py`를 또 실행하지 않는다. Container Manager의 프로젝트 화면에서 로그와 시작/중지 상태도 확인할 수 있다.

## 5. 네트워크와 방화벽

기본 권장: 공유기에서 이 앱용 **포트 포워딩을 만들지 않는다.** NAS와 휴대폰에 Tailscale을 설치하고 같은 tailnet에 로그인한다. Tailscale 관리자 콘솔에서 기기 접근 규칙을 NAS와 허용된 휴대폰으로 제한하고, HTTPS 및 MagicDNS를 켠다. NAS SSH에서 다음 명령을 실행해 로컬 API를 tailnet 안의 HTTPS 주소로 제공한다. `tailscale serve status`에 표시된 `https://NAS이름.도메인.ts.net`을 앱의 URL로 사용한다. `Funnel`은 켜지 않는다. Tailscale 패키지 CLI 경로/버전이 다르면 공식 안내를 확인한다.

```sh
sudo /var/packages/Tailscale/target/bin/tailscale serve --bg http://127.0.0.1:8787
sudo /var/packages/Tailscale/target/bin/tailscale serve status
```

DSM `제어판 > 보안 > 방화벽`에서 **자기 LAN 대역의 DSM 관리 포트**와 필요한 Tailscale 접근을 먼저 허용한 뒤, 나머지 원치 않는 인바운드를 거부한다. 규칙은 위에서 아래 순서로 첫 일치 규칙이 적용된다. 방화벽 저장 전 다른 브라우저/기기로 관리 화면 접근을 확인해 잠금을 피한다. Tailscale의 Synology TUN 구성을 사용했다면 공식 안내대로 `100.64.0.0/10` 소스 허용 규칙이 필요한지 확인한다. `8787`은 외부 허용하지 않는다. DSM의 `admin`/`guest` 계정을 비활성화하고 별도 관리자 계정에 MFA를 켠다. 자동 차단/계정 보호, 보안 어드바이저 검사, DSM·패키지 자동 업데이트, UPS와 알림 이메일도 설정한다. SMB는 LAN/VPN에만 허용한다.

공용 인터넷으로 제공해야 한다면 먼저 **사용자별 인증과 Q&A 접근 제어**를 추가해야 한다. 현재 사용자 토큰은 APK에서 추출 가능하고 `/api/qna`가 전체 질문을 반환하므로, HTTPS 역방향 프록시와 포트 포워딩만으로는 공개 서비스에 적합하지 않다. 이후 사용자 인증을 구현한 경우에는 DSM `제어판 > 로그인 포털 > 고급 > 역방향 프록시`에서 별도 앱 도메인 HTTPS 443 → `127.0.0.1:8787`을 만들고 도메인 인증서를 지정한다. 공유기에는 TCP 443만 NAS로 전달하며 HTTP 80은 인증서 발급 방식에 필요한 경우에만 임시 허용한다. DSM 5000/5001, SSH 22, API 8787, SMB 445는 포워딩하지 않는다. CGNAT/이중 NAT라면 단순 포트 포워딩은 작동하지 않으므로 VPN을 사용한다.

## 6. 앱 빌드와 확인

Tailscale Serve HTTPS 주소와 `.env`의 **사용자 토큰**으로 PC에서 빌드한다. 주소 끝에 `/datepdf`를 붙이지 않는다. 관리자 화면에 들어갈 때만 NAS `.env`의 **관리자 토큰**을 입력한다. NAS 관리자 토큰은 앱 메모리에만 보관되고 앱 재시작 뒤 다시 입력한다. 현재 Firebase 기본 빌드는 코드 `123456`을 사용하므로 Firebase를 계속 운영할 경우 별도 인증 교체가 필요하다.

```powershell
cd D:\my_portfolio\Date-Pdf
flutter pub get
flutter build apk --release --dart-define=DATEPDF_BACKEND=nas --dart-define=DATEPDF_NAS_BASE_URL=https://NAS이름.도메인.ts.net --dart-define=DATEPDF_NAS_TOKEN=<USER_TOKEN>
```

`build\app\outputs\flutter-apk\app-release.apk`를 휴대폰에 설치하고 Tailscale을 켠다. 날짜 선택/PDF 다운로드/오프라인 캐시, 제목 표시, 조회수, Q&A 질문과 관리자 답변, PDF 교체, 제목 카탈로그 저장을 확인한다. 서버 `/api/pdf/current/metadata`는 PDF 파일 정보와 페이지 수를 제공한다. 제목 자동 분석은 **Python API가 수행하지 않는다**. 관리자 앱의 `제목 카탈로그` 화면이 PDF를 읽고 OCR/레이아웃 분석 후 결과를 NAS 카탈로그에 저장한다. 실제 PDF로 365개 중 성공·저신뢰·실패 개수를 확인하고 낮은 신뢰도는 사람이 검수한다. PDF를 교체한 뒤에는 새 PDF 기준으로 제목 카탈로그도 다시 분석/검수한다.

NAS 알림은 앱이 foreground에서 실행 중일 때 30초마다 PDF 메타데이터와 Q&A 변경을 확인해 로컬 알림을 표시한다. Android/iOS는 백그라운드에서 앱 타이머 실행을 늦추거나 중단할 수 있어 전달 시점을 보장할 수 없고, 앱이 완전히 종료된 상태의 즉시 푸시는 구현되어 있지 않다. 휴대폰의 알림 권한과 앱 설정의 PDF/Q&A 알림 스위치를 켜고, 관리자 기기에서 PDF 교체 및 답변을 올린 뒤 다른 기기에서 30초 이상 대기해 확인한다. 완전 종료 상태 푸시가 필요하면 별도의 푸시 서비스와 기기 토큰 등록을 구현해야 한다.

## 오프라인 모드

NAS 백엔드 빌드에서는 앱이 NAS API 연결 상태를 확인하고, 연결이 끊기면 화면 상단에 오프라인 안내를 표시한다. PDF, PDF 제목/목록, 설정, 그리고 기기에서 마지막으로 받아 둔 Q&A는 캐시가 있는 범위에서 열람할 수 있다. 캐시는 기기 내부에 저장되므로 앱 데이터 삭제나 앱 재설치, 다른 기기에서는 기존 캐시를 사용할 수 없다.

오프라인에서는 Q&A 질문 등록, 관리자 답변 저장, 읽음 상태 변경을 할 수 없다. 입력 내용을 오프라인 대기열에 넣지 않으며, 재연결 후 자동으로 전송하지 않는다. 따라서 앱이 등록 성공으로 잘못 안내하거나 예전 오프라인 입력이 나중에 뜻하지 않게 서버로 올라가지 않는다. 연결이 회복되면 Q&A 목록은 화면이 활성화된 동안 약 30초 간격으로 다시 받아오며, 질문/답변 버튼이 활성화된다. 질문·답변 저장 도중 연결이 끊긴 경우 오류 안내가 나오고, 저장 여부가 확인되지 않았다면 서버 목록을 새로고침해 중복 제출을 피한다.

NAS API가 응답하면(인증 오류 포함) NAS 연결 자체는 가능한 것으로 판단한다. 잘못된 주소/토큰, 방화벽 차단, NAS 종료처럼 요청에 응답이 오지 않는 경우를 오프라인으로 표시한다. 앱의 백그라운드에서는 운영체제가 주기 확인을 늦추거나 멈출 수 있으므로, 알림/실시간 동기화 보장은 별도 푸시 서비스가 필요하다.

## 7. 백업·복구·운영

`Hyper Backup > + > 데이터 백업 작업 > 로컬 폴더 및 USB`에서 원본 `datepdf-data`와 필요한 DSM 설정을 선택하고 대상 `/volume2/datepdf-backup`을 고른다. 다중 버전, 일일 백업, 보존 정책(예: 30개), 주간 무결성 검사를 설정한다. SQLite WAL 사용 중이므로 파일을 임의로 `cp`하는 대신 Hyper Backup의 파일 백업 또는 API 정지 후 복사/복구를 사용한다. 별도로 주 1회 이상 외장 디스크/원격 NAS/클라우드로 보내고 한 번은 실제 복원 테스트를 한다. API는 PDF 교체 전 사본 최근 20개, JSON별 최근 30개를 `/volume1/datepdf-data/backups`에 보관한다. 같은 풀이라 재해 대비 백업은 아니다. 디스크 SMART 오류, 저장소 풀 성능 저하, 백업 실패, 용량 80% 접근 알림을 DSM에서 켠다.

복구 시 새 볼륨에 공유 폴더를 만든 뒤 Hyper Backup에서 `datepdf-data`를 복원한다. 컨테이너를 중지한 상태에서 복원하고, 데이터 폴더·권한·`.env`를 확인한 뒤 다시 시작한다. `.env`는 백업에 무조건 포함하지 말고 비밀번호 관리자에 두 토큰을 별도로 보관한다. 토큰이 노출되면 `.env` 값을 바꾸고 컨테이너를 재시작한 뒤 앱도 새 사용자 토큰으로 다시 빌드한다.

## 로컬 검증과 현재 한계

```powershell
python -m pip install -r python/nas_requirements.txt httpx pytest
python -m pytest python/test_nas_api.py -q
flutter analyze --no-pub
flutter test
```

API 통합 테스트는 사용자/관리자 권한, 잘못된 PDF 거부, 정상 PDF 다운로드, 설정, Q&A 답변과 재시도, 조회수 중복 방지를 확인한다. Flutter 테스트는 앱 시작 화면과 제목 JSON 파서를 확인한다. 실제 Synology 장비, 실 PDF 365페이지 OCR 품질, Android 푸시 표시, VPN/방화벽 실접속은 이 작업 공간에서 확인할 수 없으므로 위 체크리스트를 NAS와 휴대폰에서 수행한다. 사용자 토큰은 앱에 포함되며 현재 Q&A 전체 목록을 볼 수 있다. 민감한 Q&A나 불특정 사용자가 있는 서비스에는 사용자별 인증·데이터 분리가 선행돼야 한다.

참고: [DS1825+ 사양](https://www.synology.com/en-global/products/DS1825%2B), [DSM 저장소 풀 생성](https://kb.synology.com/en-id/DSM/help/DSM/StorageManager/storage_pool_create_storage_pool?version=7), [Container Manager 프로젝트](https://kb.synology.com/tr-tr/DSM/help/ContainerManager/docker_project?version=7), [DSM 방화벽](https://kb.synology.com/index.php/en-us/DSM/help/DSM/AdminCenter/connection_security_firewall?version=7), [Synology 백업 전략](https://kb.synology.com/en-af/DSM/tutorial/How_to_back_up_your_Synology_NAS), [Tailscale Synology](https://tailscale.com/docs/integrations/synology), [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve).
