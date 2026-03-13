import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/direct_mode_provider.dart';
import '../widgets/app_snackbar.dart';
import 'captcha_webview_page.dart';

/// 直连模式登录页面
/// 用户输入小米账号密码，无需xiaomusic服务端
class DirectModeLoginPage extends ConsumerStatefulWidget {
  const DirectModeLoginPage({super.key});

  @override
  ConsumerState<DirectModeLoginPage> createState() =>
      _DirectModeLoginPageState();
}

class _DirectModeLoginPageState extends ConsumerState<DirectModeLoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late AnimationController _animationController;
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    void listener() {
      if (mounted) setState(() {});
    }
    _accountController.addListener(listener);
    _passwordController.addListener(listener);
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 调用Provider登录
    await ref.read(directModeProvider.notifier).login(
          account: _accountController.text.trim(),
          password: _passwordController.text,
          saveCredentials: true,
        );
  }

  /// 🎯 显示 WebView 验证码页面
  /// 用户在 WebView 中完成验证后，自动重试登录
  Future<void> _showCaptchaWebView(
    BuildContext context,
    DirectModeNeedsCaptcha captchaState,
  ) async {
    debugPrint('🌐 [DirectMode] 显示 WebView 验证码页面');

    // 🎯 用于跟踪验证是否完成和提取的 Cookie
    bool verificationCompleted = false;
    Map<String, String>? extractedCookies;

    // 显示 WebView 验证码页面
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CaptchaWebViewPage(
          captchaUrl: captchaState.captchaUrl,
          onVerificationComplete: (cookies) {
            debugPrint('✅ [DirectMode] WebView 验证完成，准备重试登录');
            final safeCookies = <String, String>{};
            cookies?.forEach((k, v) {
              if (k == 'passToken' ||
                  k == 'serviceToken' ||
                  k == 'ssecurity') {
                safeCookies[k] = v.length <= 6
                    ? '***'
                    : '${v.substring(0, 3)}***${v.substring(v.length - 3)}';
              } else {
                safeCookies[k] = v;
              }
            });
            debugPrint('🍪 [DirectMode] 收到 Cookie: $safeCookies');
            verificationCompleted = true;
            extractedCookies = cookies;
          },
        ),
      ),
    );

    // 🎯 只有当验证完成后才重试登录，避免无限循环
    if (mounted && verificationCompleted) {
      debugPrint('🔄 [DirectMode] 验证完成，自动重试登录');

      // 🎯 使用提取的 Cookie 进行登录
      await ref.read(directModeProvider.notifier).loginWithCookies(
            account: captchaState.account,
            password: captchaState.password,
            cookies: extractedCookies,
            saveCredentials: true,
          );
    } else {
      debugPrint('⚠️ [DirectMode] 用户取消验证，不重试登录');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听登录状态
    final directModeState = ref.watch(directModeProvider);

    // 登录状态监听（AuthWrapper 自动处理页面跳转）
    ref.listen<DirectModeState>(directModeProvider, (previous, next) {
      if (next is DirectModeAuthenticated) {
        AppSnackBar.showSuccess(
          context,
          '登录成功！找到 ${next.devices.length} 个设备',
        );
      } else if (next is DirectModeNeedsCaptcha) {
        _showCaptchaWebView(context, next);
      } else if (next is DirectModeError) {
        AppSnackBar.showError(
          context,
          next.message,
        );
      }
    });

    final isLoading = directModeState is DirectModeLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!isLoading) {
          ref.read(playbackModeProvider.notifier).clearMode();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF1A1B22) : Colors.white,
        body: Stack(
          children: [
            // 🎨 背景装饰光晕
            if (isDark) ...[
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Positioned(
                    top: -100 + (25 * _animationController.value),
                    left: -100 + (20 * (1 - _animationController.value)),
                    child: child!,
                  );
                },
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF4081).withValues(alpha: 0.1),
                  ),
                ),
              ),
            ],

            SafeArea(
              child: Column(
                children: [
                  // 🏠 自定义导航栏
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: isDark ? Colors.white : const Color(0xFF1A1B22),
                            size: 20,
                          ),
                          onPressed: isLoading
                              ? null
                              : () => ref.read(playbackModeProvider.notifier).clearMode(),
                        ),
                        const Spacer(),
                        SvgPicture.asset(
                          'assets/hmusic-logo.svg',
                          width: 80,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF21B0A5), // 品牌 Teal
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 40),
                        const Spacer(),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 40),

                          // 🏷️ 标题区域
                          Text(
                            '直连模式',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF1A1B22),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '登录小米账号以发现局域网内的设备',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : Colors.black54,
                              height: 1.5,
                            ),
                          ),

                          const SizedBox(height: 48),

                          // 📝 登录表单
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 小米账号
                                _buildModernTextField(
                                  controller: _accountController,
                                  labelText: '小米账号',
                                  hintText: '手机号 / 邮箱 / 小米 ID',
                                  prefixIcon: Icons.account_circle_rounded,
                                  isDark: isDark,
                                  enabled: !isLoading,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return '请输入小米账号';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 24),

                                // 密码
                                _buildModernTextField(
                                  controller: _passwordController,
                                  labelText: '密码',
                                  hintText: '••••••••',
                                  prefixIcon: Icons.lock_rounded,
                                  isDark: isDark,
                                  obscureText: _obscurePassword,
                                  enabled: !isLoading,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      color: isDark ? Colors.white38 : Colors.black26,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '请输入密码';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 40),

                                // 登录按钮
                                _buildModernButton(
                                  onPressed: isLoading ? null : _handleLogin,
                                  isLoading: isLoading,
                                  title: '发现设备',
                                  isDark: isDark,
                                ),

                                const SizedBox(height: 40),

                                // 🛡️ 隐私说明
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.03)
                                        : Colors.grey.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.security_rounded, size: 16, color: const Color(0xFF2196F3)),
                                          const SizedBox(width: 8),
                                          Text(
                                            '安全与隐私',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        '你的账号信息仅用于向小米服务器获取设备 Token。HMusic 不会上传或保存你的密码。',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white38 : Colors.black54,
                                          height: 1.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData prefixIcon,
    required bool isDark,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            labelText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          validator: validator,
          style: const TextStyle(fontSize: 16, color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
            prefixIcon: Icon(prefixIcon, color: isDark ? Colors.white38 : Colors.black26, size: 22),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF2196F3), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required String title,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2196F3).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
