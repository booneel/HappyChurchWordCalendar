import 'local_profile_service.dart';

class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();
  factory AdminService() => instance;

  final LocalProfileService _profileService = LocalProfileService();

  // 기본 관리자 승인코드
  static const String defaultAdminCode = '123456';

  /// 현재 관리자 모드 활성화 여부
  Future<bool> get isSignedInAsAdmin => _profileService.isAdminMode();

  /// 6자리 승인코드 검증
  bool verifyAdminCode(String inputCode) {
    return inputCode.trim() == defaultAdminCode;
  }

  /// 관리자 모드 정식 입장
  Future<void> signInAsAdmin() async {
    await _profileService.setAdminMode(true);
  }

  /// 관리자 모드 종료 / 로그아웃
  Future<void> signOut() async {
    await _profileService.setAdminMode(false);
  }
}
