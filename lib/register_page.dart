import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'design.dart'; // unified Cropeye design import

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _register() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    String name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = "Please enter your full name");
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = "Enter a valid email address");
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = "Password must be at least 6 characters");
      return;
    }

    try {
      setState(() => _isLoading = true);

      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Registration successful!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? "Registration failed.");
    } catch (_) {
      setState(() => _errorMessage = "An error occurred. Please try again.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: "Hello",
      subtitle: "Sign up!",
      fields: [
        AuthTextField(
          icon: Icons.person,
          hint: "Full Name",
          controller: _nameController,
        ),
        AuthTextField(
          icon: Icons.email,
          hint: "Email",
          controller: _emailController,
        ),
        AuthTextField(
          icon: Icons.lock,
          hint: "Password",
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
        const SizedBox(height: 15),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
      ],
      buttonText: "Sign Up",
      onSubmit: _register,
      footerText: "Already have an account?",
      footerActionText: "Sign In",
      onFooterAction: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      },
      topIcon: const TomatoBadge(size: 90), // 🍅 realistic tomato icon
    );
  }
}
