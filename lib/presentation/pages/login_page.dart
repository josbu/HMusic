import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import '../providers/direct_mode_provider.dart';
import '../../core/constants/app_constants.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with TickerProviderStateMixin {
  late final GlobalKey<FormState> _formKey;
  late AnimationController _animationController;
  final _serverUrlController = TextEditingController(
    text: AppConstants.defaultServerUrl,
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();
    _animationController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    void listener() { if (mounted) setState(() {}); }
    _serverUrlController.addListener(listener);
    _usernameController.addListener(listener);
    _passwordController.addListener(listener);
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    ref.read(authProvider.notifier).login(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoading = authState is AuthLoading;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!isLoading) {
          ref.read(playbackModeProvider.notifier).clearMode();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B0B14) : Colors.white,
        body: Stack(
          children: [
            // 🎨 背景装饰光晕 - 蓝
            if (isDark)
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Positioned(
                    top: -200 + (40 * _animationController.value),
                    right: -150 + (30 * (1 - _animationController.value)),
                    child: child!,
                  );
                },
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                  ),
                ),
              ),

            // 🎨 背景装饰光晕 - 粉
            if (isDark)
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Positioned(
                    bottom: -150 + (50 * (1 - _animationController.value)),
                    left: -120 + (40 * _animationController.value),
                    child: child!,
                  );
                },
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF4081).withValues(alpha: 0.08),
                  ),
                ),
              ),

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
                        SizedBox(
                          height: 24, 
                          child: AspectRatio(
                            aspectRatio: 572 / 210,
                            child: SvgPicture.asset(
                              'assets/hmusic-logo.svg',
                              fit: BoxFit.contain,
                              colorFilter: ColorFilter.mode(
                                isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF21B0A5),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 40), // 视觉平衡
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
                          const SizedBox(height: 32),
                          
                          // 🏷️ 标题区域
                          Text(
                            'xiaomusic',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF1A1B22),
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '连接到你的个人音乐服务端',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.55)
                                  : Colors.black54,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 48),

                          // 📝 登录表单
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 服务器地址
                                _buildModernTextField(
                                  controller: _serverUrlController,
                                  labelText: '服务器地址',
                                  hintText: 'http://192.168.1.100:8090',
                                  prefixIcon: Icons.dns_rounded,
                                  isDark: isDark,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '请输入服务器地址';
                                    }
                                    return null;
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, top: 8, bottom: 20),
                                  child: Text(
                                    '🎯 正在探测局域网服务器...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: const Color(0xFF2196F3).withValues(alpha: 0.8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                                // 用户名
                                _buildModernTextField(
                                  controller: _usernameController,
                                  labelText: '账号 (可选)',
                                  hintText: '未设置可留空',
                                  prefixIcon: Icons.person_rounded,
                                  isDark: isDark,
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
                                ),

                                const SizedBox(height: 40),

                                // 登录按钮
                                _buildModernButton(
                                  onPressed: isLoading ? null : _handleLogin,
                                  isLoading: isLoading,
                                  title: '连接服务器',
                                  isDark: isDark,
                                ),

                                const SizedBox(height: 32),

                                // 辅助链接
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '查看设置指南',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? const Color(0xFF2196F3) : Colors.blue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Text(
                                      '帮助中心',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? const Color(0xFF2196F3) : Colors.blue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 40),

                          if (authState is AuthError)
                             Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                authState.message,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
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
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFFF4081), width: 1.5),
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
        color: const Color(0xFFFF4081),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4081).withValues(alpha: 0.35),
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
