import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_colors.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController(); // Profil için gerekli
  bool _isLoading = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    setState(() => _isLoading = true);
    try {
      final input = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (input.isEmpty || password.isEmpty) {
        throw const AuthException(
          "Email/Username and password cannot be empty",
        );
      }

      if (_isSignUp) {
        final username = _usernameController.text.trim();
        if (username.isEmpty) {
          throw const AuthException("Username cannot be empty");
        }

        // Check if username is already taken before signing up
        final existingUser = await Supabase.instance.client
            .from('profiles')
            .select('username')
            .eq('username', username)
            .maybeSingle();

        if (existingUser != null) {
          throw const AuthException("Username is already taken");
        }

        // Kayıt olurken username'i 'data' içine koyuyoruz ki SQL Trigger çalışsın
        await Supabase.instance.client.auth.signUp(
          email: input,
          password: password,
          data: {'username': username},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Success! Check your email for confirmation."),
            ),
          );
        }
      } else {
        String emailToUse = input;

        // If input doesn't contain '@', it's likely a username
        if (!input.contains('@')) {
          final response = await Supabase.instance.client
              .from('profiles')
              .select('email')
              .eq('username', input)
              .maybeSingle();

          if (response == null || response['email'] == null) {
            throw const AuthException("User not found with this username");
          }
          emailToUse = response['email'] as String;
        }

        await Supabase.instance.client.auth.signInWithPassword(
          email: emailToUse,
          password: password,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("An error occurred: $e"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // --- YENİ LOGO KISMI BURASI ---
              ClipRRect(
                borderRadius: BorderRadius.circular(28), // Premium oval köşeler
                child: Image.asset(
                  'assets/logo.png', // Fotoğrafının uzantısı .jpg ise burayı logo.jpg yapmayı unutma
                  width: 150, // Logonun büyüklüğü (isteğine göre büyütebilirsin)
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 40),
              // ------------------------------

              if (_isSignUp) ...[
                _buildTextField(
                  _usernameController,
                  "Username",
                  Icons.person,
                  false,
                ),
                const SizedBox(height: 16),
              ],
              _buildTextField(
                _emailController,
                _isSignUp ? "Email" : "Email or Username",
                Icons.email,
                false,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                _passwordController,
                "Password",
                Icons.lock,
                true,
              ),
              const SizedBox(height: 24),

              _isLoading
                  ? const CircularProgressIndicator(color: AppColors.accent)
                  : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _handleAuth,
                child: Text(
                  _isSignUp ? "CREATE ACCOUNT" : "SIGN IN",
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: _isSignUp
                    ? RichText(
                        text: const TextSpan(
                          text: "Already have an account? ",
                          style: TextStyle(color: AppColors.textSecondary),
                          children: [
                            TextSpan(
                              text: "Sign In",
                              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : RichText(
                        text: const TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: AppColors.textSecondary),
                          children: [
                            TextSpan(
                              text: "Join Episod",
                              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String hint,
      IconData icon,
      bool isPassword,
      ) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        hintText: hint,
        hintStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}