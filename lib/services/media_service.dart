import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class MediaService {
  final ImagePicker _picker = ImagePicker();

  // Captura foto da câmera
  Future<File?> tirarFoto() async {
    final XFile? foto = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (foto != null) return File(foto.path);
    return null;
  }

  // Seleciona foto da galeria
  Future<File?> selecionarDaGaleria() async {
    final XFile? imagem = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (imagem != null) return File(imagem.path);
    return null;
  }

  /// No Windows (e em outros desktops) o image_picker só abre a câmera com um
  /// "cameraDelegate"; sem ele, pedir a câmera lança StateError. A opção só
  /// aparece no menu quando a plataforma suporta.
  bool get cameraDisponivel => _picker.supportsImageSource(ImageSource.camera);

  /// No Android, o sistema pode destruir a Activity do app enquanto a câmera
  /// está aberta (pouca memória). A foto tirada não volta pelo pickImage: o
  /// plugin guarda o resultado até o app pedir com retrieveLostData.
  Future<File?> recuperarFotoPerdida() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    final resposta = await _picker.retrieveLostData();
    if (resposta.isEmpty) return null;
    if (resposta.exception != null) throw resposta.exception!;
    final foto = resposta.file;
    return foto != null ? File(foto.path) : null;
  }
}

/// Texto em português para as falhas da câmera e da galeria. Sem tratamento,
/// essas exceções escapavam do onTap e a foto simplesmente não aparecia.
String mensagemDeErroMidia(Object erro) {
  if (erro is PlatformException) {
    switch (erro.code) {
      case 'camera_access_denied':
        return 'Acesso à câmera negado. Libere a permissão nas configurações '
            'do aparelho.';
      case 'photo_access_denied':
        return 'Acesso à galeria negado. Libere a permissão nas configurações '
            'do aparelho.';
      case 'no_available_camera':
        return 'Nenhuma câmera disponível neste aparelho.';
    }
  }
  return 'Não foi possível carregar a imagem. Tente novamente.';
}
