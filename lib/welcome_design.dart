// welcome_design.dart — v8 (static background + soft bottom fade)
import 'package:flutter/material.dart';

class WelcomeDesign extends StatelessWidget {
  const WelcomeDesign({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image (high-quality fit)
        const DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/Welcome_Screen2.jpg'),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),

        // Subtle fade overlay from transparent (top) to blackish (bottom)
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.15),
                  Colors.black.withOpacity(0.45),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
