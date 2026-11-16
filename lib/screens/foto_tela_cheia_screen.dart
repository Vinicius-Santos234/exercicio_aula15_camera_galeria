import 'dart:io';

import 'package:flutter/material.dart';

/// Tag compartilhada pelo avatar e pela foto em tela cheia: o Hero anima a
/// foto saindo do círculo do perfil até ocupar a tela.
const tagFotoPerfil = 'foto-perfil';

/// Desafio Intermediário: foto em tela cheia com zoom.
class FotoTelaCheiaScreen extends StatefulWidget {
  const FotoTelaCheiaScreen({super.key, required this.foto});

  final File foto;

  @override
  State<FotoTelaCheiaScreen> createState() => _FotoTelaCheiaScreenState();
}

class _FotoTelaCheiaScreenState extends State<FotoTelaCheiaScreen> {
  static const _zoomDoToqueDuplo = 2.5;

  final _transformacao = TransformationController();
  Offset _pontoDoToque = Offset.zero;

  /// Pinça amplia livremente (até 5x). O toque duplo alterna entre 2,5x no
  /// ponto tocado e o tamanho original.
  void _alternarZoom() {
    if (_transformacao.value.getMaxScaleOnAxis() > 1) {
      _transformacao.value = Matrix4.identity();
      return;
    }
    const s = _zoomDoToqueDuplo;
    _transformacao.value = Matrix4.diagonal3Values(s, s, 1)
      ..setTranslationRaw(
        -_pontoDoToque.dx * (s - 1),
        -_pontoDoToque.dy * (s - 1),
        0,
      );
  }

  @override
  void dispose() {
    _transformacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Foto de Perfil'),
      ),
      body: GestureDetector(
        onDoubleTapDown: (detalhes) => _pontoDoToque = detalhes.localPosition,
        onDoubleTap: _alternarZoom,
        child: InteractiveViewer(
          transformationController: _transformacao,
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(
            child: Hero(
              tag: tagFotoPerfil,
              child: Image.file(widget.foto, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Use dois dedos ou toque duas vezes para dar zoom',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
