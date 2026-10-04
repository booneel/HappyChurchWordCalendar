import 'local_profile_service.dart';
import 'backend_config.dart';
import 'nas_api_client.dart';

class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();
  factory AdminService() => instance;

  final LocalProfileService _profileService = LocalProfileService();

  // 기본 관리자 승인코드
  static const String defaultAdminCode = '123456';

  /// 현재 관리자 모드 활성화 여부
  Future<bool> get isSignedInAsAdmin async => BackendConfig.useNas
      ? NasApiClient.instance.hasAdminToken
      : _profileService.isAdminMode();

  /// 6자리 승인코드 검증
  Future<bool> verifyAdminCode(String inputCode) async {
    if (BackendConfig.useNas) {
      return NasApiClient.instance.verifyAdminToken(inputCode.trim());
    }
    return inputCode.trim() == defaultAdminCode;
  }

  /// 관리자 모드 정식 입장
  Future<void> signInAsAdmin() async {
    await _profileService.setAdminMode(true);
  }

  /// 관리자 모드 종료 / 로그아웃
  Future<void> signOut() async {
    if (BackendConfig.useNas) NasApiClient.instance.setAdminToken(null);
    await _profileService.setAdminMode(false);
  }
}
