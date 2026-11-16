import 'dart:io';

import 'package:flutter/material.dart';

import '../services/foto_perfil_storage.dart';
import '../services/media_service.dart';
import 'foto_tela_cheia_screen.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _mediaService = MediaService();
  final _fotoStorage = FotoPerfilStorage();
  File? _imagemPerfil;
  final _nomeController = TextEditingController(text: 'Diego Menegassi');

  @override
  void initState() {
    super.initState();
    _carregarFotoSalva();
  }

  /// Desafio Avançado: ao abrir o app, volta a foto da execução anterior.
  Future<void> _carregarFotoSalva() async {
    final foto = await _fotoStorage.carregar();
    if (foto != null && mounted) {
      setState(() => _imagemPerfil = foto);
    }
  }

  Future<void> _capturarImagem(bool daCamera) async {
    Navigator.pop(context);
    final File? imagem = daCamera
        ? await _mediaService.tirarFoto()
        : await _mediaService.selecionarDaGaleria();

    if (imagem != null) {
      // Desafio Avançado: grava a foto antes de exibir
      final salva = await _fotoStorage.salvar(imagem);
      setState(() {
        _imagemPerfil = salva;
      });
    }
  }

  void _exibirOpcoesMidia() {
    showModalBottomSheet(
      context: context,
      // A altura fixa de 160 do roteiro só comporta duas opções. Com a
      // terceira (Remover Foto), a coluna passa a ocupar só o necessário.
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                // O roteiro usa Colors.rose, que não existe no Flutter (erro de
                // compilação). Colors.pink é o tom rosa equivalente.
                leading: const Icon(Icons.camera_alt, color: Colors.pink),
                title: const Text('Tirar Foto com a Câmera'),
                onTap: () => _capturarImagem(true),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.pink),
                title: const Text('Escolher da Galeria'),
                onTap: () => _capturarImagem(false),
              ),
              // Desafio Básico: só aparece quando há uma foto para remover
              if (_imagemPerfil != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Remover Foto'),
                  onTap: _removerFoto,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _removerFoto() {
    Navigator.pop(context);
    setState(() {
      _imagemPerfil = null;
    });
    // Desafio Avançado: a remoção também vale para a próxima abertura
    _fotoStorage.remover();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Foto removida. Avatar padrão restaurado.')),
    );
  }

  void _abrirTelaCheia() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FotoTelaCheiaScreen(foto: _imagemPerfil!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil do Usuário'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  // Desafio Intermediário: tocar na foto abre a tela cheia
                  Semantics(
                    button: _imagemPerfil != null,
                    label: _imagemPerfil != null
                        ? 'Ver foto em tela cheia'
                        : 'Avatar padrão',
                    child: GestureDetector(
                      onTap: _imagemPerfil != null ? _abrirTelaCheia : null,
                      child: Hero(
                        tag: tagFotoPerfil,
                        child: CircleAvatar(
                          radius: 70,
                          backgroundColor: Colors.pink.shade100,
                          backgroundImage: _imagemPerfil != null
                              ? FileImage(_imagemPerfil!)
                              : null,
                          child: _imagemPerfil == null
                              ? const Icon(
                                  Icons.person,
                                  size: 70,
                                  color: Colors.pink,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: FloatingActionButton.small(
                      onPressed: _exibirOpcoesMidia,
                      child: const Icon(Icons.camera_alt),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome Completo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
