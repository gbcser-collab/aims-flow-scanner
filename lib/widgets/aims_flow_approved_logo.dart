// Approved AIMS Flow mark recovered from the V9 approved logo artifact.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

const _aimsFlowApprovedLogoBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAMAAABlApw1AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAdpQTFRFAAAAVMX4VMX4AUN3AVGRAVaaAVebKbb2VMX4FmOXVMX4VMX4Kbb2AUuGAUuHAVWXAVebFmyWKbb2LLf2VMX4AClIACxOACxPAC1QAC5RAC5SAC9TAC9UADBWADFWADFXADNaADVeADZgADdgADtpADxsASZCASZDASpJATFXATRbATRcATRdATVfATZgAThjAThkATlmATpnATpoATtpATxqAT1sAT1tAT5tAT5uAT5vAT9vAT9wAUByAUFzAUF0AUJ1AUJ2AUR5AUR6AUV6AUV7AUZ8AUd+AUd/AUiAAUiBAUmCAUmDAUqDAUqEAUqFAUuEAUuFAUuGAUuHAUyHAUyIAUyJAU2IAU2JAU2KAU6KAU6LAU6MAU+MAU+NAVCOAVCPAVCQAVGPAVGQAVGRAVKRAVKSAVOSAVOTAVOUAVOVAVSUAVSVAVSWAVWWAVWXAVWYAVWZAVaYAVaZAVaaAVeaAVebAi5PAjFWAjRbAjdgAjpkAjxoAj5rAkBuAkFxAkJzAkN1AkR2AkV4AkZ5AkZ6Akd6FmiPFmmQF22WF3CbGHOfGXajGXmnGXuqGn2tGn+wGoCyG4K0G4O2G4S3G4W4G4W5G4a6HIa7H4vAKbb2LLf2TML4VMX4KQGaCAAAABV0Uk5TABAgMDAwMDAwQEDP3+/v7+/v7+/v7Yl3rQAAAz5JREFUeNrt1AdTE1EUhmFEQKygYi9YsTewYcOAEBBRg6KIkASBmKhhkazXLnbsvUb8r2bNMASy2b33zmzmnJnv+wF7nnd2dgsKMAzL60or/uqtohR++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++Gn7C2dprpCGX/uhs6fBDz/88HPxa9+i4te9Rsevd4+SX+ciLb/6TWp+1av0/Gp3KfpVLtP0y9+m6pe9Ttcvd5+yX0ZA2+9uoO53U9D3Ozuc/DMWjpHwOxU4+hck/4yR8OcucPEntQo88OcqcPXrFHjity+Q8KsXeOS3K5DyqxZ45s8ukPSrFXjon1og7Vcp8NQ/uUDBL1/gsT+zQMkvW+C5f6JA0S9XkAf/eIGyX6YgL/50gYbfvSBPfqtAy+9WkDd/qkDP71yQR7/THP1OBTz8uQu4+HMV8PHbF3Dy2xXw8mcXcPNPLeDnn1zA0Z9ZwNM/UcDVP17A158u4Oy3Coj4C+Yk9fZ7Jg2/7hv49XJuEeeCny/a+8qK+RZY/kGzvIRrwY/n7b3xhBBcC74/O5vy3xJcC749bQvFb5pWAMuCr09ag9eHzHQAw4Ivj1u6o0YiFcCz4POIv6s/PjwRwKzg06OmjiuxwcwAVgUfH9YHgpGYYWQGMCr48MDX2hWOxuLGsDn+FXMqeH//qP9cT+/VrAAmBe/uHWw4dSHYF8kOYFHw9u5eX/OZzmA4ErthTPqKeRS8ubPrSENLoLMnPGAXQL7g9e3t++oaTwY6u8MDUbsA4gWvNm/ZXetrbDl9sTvUH72W/o8KwaZgdNOSbdWHrICOy6E+6z9qiuzRLRitWrRyR83h4yea285bAUZC2I5qQcq/ePXOmtq6Bn8qIDIkco5mgeVfVrmu+sCxen9X1BROo1jw37+8cu2e/c2hhHAbvYK0f8WqDW1DQmbUCtL+9U0RITtaBZZ/jU9eT61gtGrpxkumUBydgvlbG/sNZT+hgunztPyECorKtPyECorLBfOCEhSgAAUoQAEKUIACFKAABShAAZkCDKO1f/OiyBBYvwCtAAAAAElFTkSuQmCC';

Uint8List? _cachedLogoBytes;

class AimsFlowApprovedLogo extends StatelessWidget {
  const AimsFlowApprovedLogo({
    super.key,
    this.size = 42,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    _cachedLogoBytes ??= base64Decode(_aimsFlowApprovedLogoBase64);
    return Image.memory(
      _cachedLogoBytes!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
  }
}
