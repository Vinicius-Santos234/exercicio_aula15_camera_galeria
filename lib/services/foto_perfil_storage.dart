import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Desafio Avançado: mantém a foto de perfil depois de reiniciar o app.
///
/// O image_picker devolve a foto na pasta de cache do app, que o sistema pode
/// limpar a qualquer momento (a documentação do pacote avisa isso). Por isso a
/// foto é copiada para a pasta de documentos do app, e é o caminho dessa cópia
/// que fica gravado no SharedPreferences.
class FotoPerfilStorage {
  static const chaveCaminho = 'key_foto_perfil_path';

  /// Copia a foto para a pasta do app, grava o caminho e apaga a cópia
  /// anterior. Devolve a cópia, que é o arquivo exibido daqui em diante.
  Future<File> salvar(File foto) async {
    final pasta = await getApplicationDocumentsDirectory();
    // Nome novo a cada foto: o FileImage guarda as imagens em cache pelo
    // caminho, e sobrescrever o mesmo arquivo mostraria a foto antiga.
    final nome =
        'foto_perfil_${DateTime.now().millisecondsSinceEpoch}'
        '${_extensao(foto.path)}';
    final copia = await foto.copy(
      '${pasta.path}${Platform.pathSeparator}$nome',
    );

    final prefs = await SharedPreferences.getInstance();
    final anterior = prefs.getString(chaveCaminho);
    await prefs.setString(chaveCaminho, copia.path);
    if (anterior != null && anterior != copia.path) await _apagar(anterior);
    return copia;
  }

  /// Foto salva numa execução anterior. Devolve null se não houver nenhuma
  /// ou se o arquivo tiver sumido do disco (nesse caso a chave é limpa).
  Future<File?> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final caminho = prefs.getString(chaveCaminho);
    if (caminho == null) return null;

    final foto = File(caminho);
    if (await foto.exists()) return foto;
    await prefs.remove(chaveCaminho);
    return null;
  }

  /// Apaga a chave e a cópia da foto.
  Future<void> remover() async {
    final prefs = await SharedPreferences.getInstance();
    final caminho = prefs.getString(chaveCaminho);
    await prefs.remove(chaveCaminho);
    if (caminho != null) await _apagar(caminho);
  }

  /// Limpeza da cópia antiga. A chave já foi trocada ou removida, então a
  /// foto não volta mesmo se o arquivo ficar. No Windows, apagar falha
  /// enquanto a imagem ainda está sendo lida para a tela; isso não deve
  /// virar erro para o usuário.
  Future<void> _apagar(String caminho) async {
    try {
      final arquivo = File(caminho);
      if (await arquivo.exists()) await arquivo.delete();
    } on FileSystemException {
      // Fica para a próxima limpeza
    }
  }

  String _extensao(String caminho) {
    final nome = caminho.split(RegExp(r'[\\/]')).last;
    final ponto = nome.lastIndexOf('.');
    return ponto > 0 ? nome.substring(ponto).toLowerCase() : '.jpg';
  }
}
