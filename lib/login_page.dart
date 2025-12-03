import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart';
import 'homepage.dart';
import 'reset_password_page.dart';
import 'design.dart'; // ✅ unified Cropeye design import

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = "Enter a valid email address");
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = "Enter your password");
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Login successful!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _firebaseErrorMessage(e.code);
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _firebaseErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Invalid email format.';
      case 'user-disabled':
        return 'This user has been disabled.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome Back!',
      subtitle: 'Sign in to continue',
      fields: [
        AuthTextField(
          icon: Icons.email_outlined,
          hint: 'Email',
          controller: _emailController,
        ),
        AuthTextField(
          icon: Icons.lock_outline,
          hint: 'Password',
          controller: _passwordController,
          obscure: true,
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        const SizedBox(height: 10),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: CircularProgressIndicator(
              color: Color(0xFF2E7D32),
              strokeWidth: 3,
            ),
          ),
        if (!_isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
              ),
              child: const Text(
                "Forgot Password?",
                style: TextStyle(
                  color: Color(0xFFE53935),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
      buttonText: 'Sign In',
      onSubmit: _login,
      footerText: "Don't have an account?",
      footerActionText: "Sign up",
      onFooterAction: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RegisterPage()),
        );
      },
      topIcon: const TomatoBadge(size: 80), // 🍅 replaced leaf icon with tomato
    );
  }
}
