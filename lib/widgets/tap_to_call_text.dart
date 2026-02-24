import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TapToCallText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  const TapToCallText(this.text, {super.key, this.style, this.textAlign});

  Future<void> _launchDialer(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      debugPrint("Could not launch dialer for $phoneNumber");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Regex to check if the string contains a phone number structure
    // (Simple check: looks for digits, assuming the input IS the phone field)
    final bool isPhone = RegExp(r'[0-9]{10}').hasMatch(text);

    if (isPhone) {
      return InkWell(
        onTap: () => _launchDialer(text),
        child: Text(
          text,
          style: (style ?? const TextStyle()).copyWith(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
          textAlign: textAlign,
        ),
      );
    }

    // For non-phone text, make it copyable
    return SelectableText(text, style: style, textAlign: textAlign);
  }
}
