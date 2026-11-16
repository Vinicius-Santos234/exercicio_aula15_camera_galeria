// Testes da câmera e galeria da Aula 15.
//
// A câmera e a galeria são simuladas trocando ImagePickerPlatform.instance por
// um FakeImagePicker: o app continua chamando ImagePicker().pickImage, mas o
// XFile devolvido aponta para um PNG de verdade criado numa pasta temporária.
// A pasta de documentos do app (path_provider) também aponta para essa pasta,
// e o SharedPreferences usa o mock em memória. Assim a cópia da foto, a
// gravação do caminho e a leitura na reabertura acontecem de fato no disco.
//
// Cobrem o MediaService, o FotoPerfilStorage, a tela do roteiro, os três
// desafios e as correções.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdm_aula15_camera_galeria/main.dart';
import 'package:pdm_aula15_camera_galeria/screens/foto_tela_cheia_screen.dart';
import 'package:pdm_aula15_camera_galeria/services/foto_perfil_storage.dart';
import 'package:pdm_aula15_camera_galeria/services/media_service.dart';

/// PNG de 1 × 1 pixel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class FakeImagePicker extends ImagePickerPlatform {
  XFile? resultado;
  Object? erro;
  Completer<XFile?>? pendente;
  bool suportaCamera = true;
  LostDataResponse fotoPerdida = LostDataResponse.empty();

  ImageSource? ultimaOrigem;
  ImagePickerOptions? ultimasOpcoes;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    ultimaOrigem = source;
    ultimasOpcoes = options;
    if (erro != null) throw erro!;
    if (pendente != null) return pendente!.future;
    return resultado;
  }

  @override
  bool supportsImageSource(ImageSource source) =>
      source == ImageSource.gallery || suportaCamera;

  @override
  Future<LostDataResponse> getLostData() async => fotoPerdida;
}

class FakePathProvider extends PathProviderPlatform {
  FakePathProvider(this.documentos);

  final String documentos;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentos;
}

late FakeImagePicker picker;
late Directory raiz;
late Directory cache;
late Directory documentos;

/// Cria um PNG na "pasta de cache", como o image_picker faz.
File _fotoNoCache(String nome) {
  final arquivo = File('${cache.path}${Platform.pathSeparator}$nome');
  arquivo.writeAsBytesSync(_png);
  return arquivo;
}

List<File> _arquivosEmDocumentos() =>
    documentos.listSync().whereType<File>().toList();

Future<String?> _caminhoSalvo() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(FotoPerfilStorage.chaveCaminho);
}

/// A cópia e a checagem do arquivo são E/S de verdade, que só termina quando
/// o laço de eventos real roda (runAsync). Cada volta deixa uma etapa
/// terminar e o pump aplica o resultado na tela.
Future<void> _aguardarDisco(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

/// Roda o laço real até o ImageCache ter a imagem decodificada.
Future<void> _aguardarImagemCarregada(
  WidgetTester tester,
  ImageProvider imagem,
) async {
  for (var i = 0; i < 30; i++) {
    final status = PaintingBinding.instance.imageCache.statusForKey(imagem);
    if (status.tracked && !status.pending) return;
    await _aguardarDisco(tester);
  }
  fail('A imagem não terminou de carregar');
}

Future<void> _abrirApp(WidgetTester tester) async {
  await tester.pumpWidget(const MeuApp());
  await _aguardarDisco(tester);
}

Future<void> _abrirMenu(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

Future<void> _escolherOpcao(WidgetTester tester, String opcao) async {
  await _abrirMenu(tester);
  await tester.tap(find.text(opcao));
  await tester.pump();
  await _aguardarDisco(tester);
  await tester.pumpAndSettle();
}

CircleAvatar _avatar(WidgetTester tester) =>
    tester.widget<CircleAvatar>(find.byType(CircleAvatar));

String? _caminhoNoAvatar(WidgetTester tester) {
  final imagem = _avatar(tester).backgroundImage;
  return imagem is FileImage ? imagem.file.path : null;
}

void main() {
  setUp(() {
    raiz = Directory.systemTemp.createTempSync('aula15_');
    cache = Directory('${raiz.path}${Platform.pathSeparator}cache')
      ..createSync();
    documentos = Directory('${raiz.path}${Platform.pathSeparator}documentos')
      ..createSync();

    picker = FakeImagePicker();
    ImagePickerPlatform.instance = picker;
    PathProviderPlatform.instance = FakePathProvider(documentos.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // Arquivo ainda aberto pelo decodificador de imagem: o SO limpa depois
    }
  });

  group('MediaService', () {
    test('tirarFoto pede a câmera com qualidade 85 e largura 1080', () async {
      final foto = _fotoNoCache('camera.png');
      picker.resultado = XFile(foto.path);

      final arquivo = await MediaService().tirarFoto();

      expect(arquivo, isA<File>());
      expect(arquivo!.path, foto.path);
      expect(picker.ultimaOrigem, ImageSource.camera);
      expect(picker.ultimasOpcoes?.imageQuality, 85);
      expect(picker.ultimasOpcoes?.maxWidth, 1080);
    });

    test('selecionarDaGaleria usa a galeria; cancelar devolve null', () async {
      expect(await MediaService().selecionarDaGaleria(), isNull);
      expect(picker.ultimaOrigem, ImageSource.gallery);
      expect(picker.ultimasOpcoes?.imageQuality, 85);
      expect(picker.ultimasOpcoes?.maxWidth, 1080);
    });

    test('cameraDisponivel segue o supportsImageSource da plataforma', () {
      expect(MediaService().cameraDisponivel, isTrue);
      picker.suportaCamera = false;
      expect(MediaService().cameraDisponivel, isFalse);
    });

    test('recuperarFotoPerdida devolve a foto guardada pelo Android', () async {
      expect(await MediaService().recuperarFotoPerdida(), isNull);

      final foto = _fotoNoCache('perdida.png');
      picker.fotoPerdida = LostDataResponse(
        file: XFile(foto.path),
        type: RetrieveType.image,
      );
      expect((await MediaService().recuperarFotoPerdida())?.path, foto.path);

      picker.fotoPerdida = LostDataResponse(
        exception: PlatformException(code: 'camera_access_denied'),
        type: RetrieveType.image,
      );
      await expectLater(
        MediaService().recuperarFotoPerdida(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('mensagemDeErroMidia traduz os códigos do image_picker', () {
      expect(
        mensagemDeErroMidia(PlatformException(code: 'camera_access_denied')),
        startsWith('Acesso à câmera negado.'),
      );
      expect(
        mensagemDeErroMidia(PlatformException(code: 'photo_access_denied')),
        startsWith('Acesso à galeria negado.'),
      );
      expect(
        mensagemDeErroMidia(PlatformException(code: 'no_available_camera')),
        'Nenhuma câmera disponível neste aparelho.',
      );
      expect(
        mensagemDeErroMidia(StateError('sem cameraDelegate')),
        'Não foi possível carregar a imagem. Tente novamente.',
      );
    });
  });

  group('FotoPerfilStorage (Desafio Avançado)', () {
    test(
      'salvar copia a foto para a pasta de documentos e grava o caminho',
      () async {
        final original = _fotoNoCache('scaled_123.png');

        final copia = await FotoPerfilStorage().salvar(original);

        expect(copia.parent.path, documentos.path);
        expect(copia.path, endsWith('.png'));
        expect(copia.readAsBytesSync(), _png);
        expect(await _caminhoSalvo(), copia.path);
        // O original no cache continua lá; quem decide apagá-lo é o sistema
        expect(original.existsSync(), isTrue);
      },
    );

    test('salvar uma foto nova apaga a cópia anterior', () async {
      final storage = FotoPerfilStorage();
      final primeira = await storage.salvar(_fotoNoCache('a.png'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final segunda = await storage.salvar(_fotoNoCache('b.jpg'));

      expect(primeira.existsSync(), isFalse);
      expect(_arquivosEmDocumentos().map((f) => f.path), [segunda.path]);
      expect(await _caminhoSalvo(), segunda.path);
    });

    test(
      'carregar devolve a foto salva; arquivo sumido limpa a chave',
      () async {
        final storage = FotoPerfilStorage();
        expect(await storage.carregar(), isNull);

        final copia = await storage.salvar(_fotoNoCache('perfil.png'));
        expect((await storage.carregar())?.path, copia.path);

        copia.deleteSync();
        expect(await storage.carregar(), isNull);
        expect(await _caminhoSalvo(), isNull);
      },
    );

    test('remover apaga a chave e a cópia', () async {
      final storage = FotoPerfilStorage();
      final copia = await storage.salvar(_fotoNoCache('perfil.png'));

      await storage.remover();

      expect(await _caminhoSalvo(), isNull);
      expect(copia.existsSync(), isFalse);
    });
  });

  group('Tela de perfil (roteiro)', () {
    testWidgets('sem foto mostra o avatar padrão e o nome do roteiro', (
      tester,
    ) async {
      await _abrirApp(tester);

      expect(find.text('Perfil do Usuário'), findsOneWidget);
      expect(_avatar(tester).backgroundImage, isNull);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Diego Menegassi'), findsOneWidget);
      expect(find.text('Nome Completo'), findsOneWidget);
    });

    testWidgets('o botão da câmera abre o ModalBottomSheet com as origens', (
      tester,
    ) async {
      await _abrirApp(tester);

      await _abrirMenu(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Tirar Foto com a Câmera'), findsOneWidget);
      expect(find.text('Escolher da Galeria'), findsOneWidget);
      expect(find.text('Remover Foto'), findsNothing);
    });

    testWidgets('a foto da galeria fecha o menu e aparece no CircleAvatar', (
      tester,
    ) async {
      picker.resultado = XFile(_fotoNoCache('galeria.png').path);
      await _abrirApp(tester);

      await _escolherOpcao(tester, 'Escolher da Galeria');

      expect(find.byType(BottomSheet), findsNothing);
      expect(picker.ultimaOrigem, ImageSource.gallery);
      expect(_caminhoNoAvatar(tester), isNotNull);
      expect(find.byIcon(Icons.person), findsNothing);
    });

    testWidgets('Tirar Foto usa ImageSource.camera', (tester) async {
      picker.resultado = XFile(_fotoNoCache('camera.png').path);
      await _abrirApp(tester);

      await _escolherOpcao(tester, 'Tirar Foto com a Câmera');

      expect(picker.ultimaOrigem, ImageSource.camera);
      expect(_caminhoNoAvatar(tester), isNotNull);
    });

    testWidgets('cancelar a câmera mantém o avatar padrão', (tester) async {
      await _abrirApp(tester);

      await _escolherOpcao(tester, 'Tirar Foto com a Câmera');

      expect(_avatar(tester).backgroundImage, isNull);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(await _caminhoSalvo(), isNull);
    });
  });

  group('Desafio Básico — Remover Foto', () {
    testWidgets('a opção só aparece com foto e restaura o avatar padrão', (
      tester,
    ) async {
      picker.resultado = XFile(_fotoNoCache('galeria.png').path);
      await _abrirApp(tester);
      await _escolherOpcao(tester, 'Escolher da Galeria');

      await _abrirMenu(tester);
      expect(find.text('Remover Foto'), findsOneWidget);
      await tester.tap(find.text('Remover Foto'));
      await tester.pump();
      await _aguardarDisco(tester);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(_avatar(tester).backgroundImage, isNull);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(
        find.text('Foto removida. Avatar padrão restaurado.'),
        findsOneWidget,
      );

      await _abrirMenu(tester);
      expect(find.text('Remover Foto'), findsNothing);
    });
  });

  group('Desafio Intermediário — tela cheia com Hero e zoom', () {
    testWidgets('sem foto, tocar no avatar não abre nada', (tester) async {
      await _abrirApp(tester);

      await tester.tap(find.byType(CircleAvatar));
      await tester.pumpAndSettle();

      expect(find.byType(FotoTelaCheiaScreen), findsNothing);
    });

    testWidgets(
      'tocar na foto abre a tela cheia com Hero e InteractiveViewer',
      (tester) async {
        picker.resultado = XFile(_fotoNoCache('galeria.png').path);
        await _abrirApp(tester);
        await _escolherOpcao(tester, 'Escolher da Galeria');
        final caminho = _caminhoNoAvatar(tester);

        final heroDoAvatar = tester.widget<Hero>(
          find.ancestor(
            of: find.byType(CircleAvatar),
            matching: find.byType(Hero),
          ),
        );
        expect(heroDoAvatar.tag, tagFotoPerfil);

        await tester.tap(find.bySemanticsLabel('Ver foto em tela cheia'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        // No meio da transição o Hero está voando entre as duas telas
        expect(find.byType(Hero), findsWidgets);
        await tester.pumpAndSettle();

        expect(find.byType(FotoTelaCheiaScreen), findsOneWidget);
        expect(find.text('Foto de Perfil'), findsOneWidget);
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(viewer.minScale, 1);
        expect(viewer.maxScale, 5);
        final imagem = tester.widget<Image>(
          find.descendant(
            of: find.byType(FotoTelaCheiaScreen),
            matching: find.byType(Image),
          ),
        );
        expect((imagem.image as FileImage).file.path, caminho);
        expect(
          tester
              .widget<Hero>(
                find.ancestor(
                  of: find.byWidget(imagem),
                  matching: find.byType(Hero),
                ),
              )
              .tag,
          tagFotoPerfil,
        );

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(FotoTelaCheiaScreen), findsNothing);
        expect(find.text('Perfil do Usuário'), findsOneWidget);
      },
    );

    testWidgets('toque duplo amplia 2,5x e o seguinte volta ao normal', (
      tester,
    ) async {
      final foto = _fotoNoCache('galeria.png');
      await tester.pumpWidget(
        MaterialApp(home: FotoTelaCheiaScreen(foto: foto)),
      );
      await tester.pump();

      double escala() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis();

      Future<void> toqueDuplo() async {
        final centro = tester.getCenter(find.byType(InteractiveViewer));
        await tester.tapAt(centro);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(centro);
        await tester.pumpAndSettle();
      }

      expect(escala(), 1);
      await toqueDuplo();
      expect(escala(), closeTo(2.5, 0.001));
      await toqueDuplo();
      expect(escala(), 1);
    });
  });

  group('Desafio Avançado — foto mantida após reiniciar', () {
    testWidgets('a foto escolhida é copiada e o caminho vai para o disco', (
      tester,
    ) async {
      final original = _fotoNoCache('scaled_galeria.png');
      picker.resultado = XFile(original.path);
      await _abrirApp(tester);

      await _escolherOpcao(tester, 'Escolher da Galeria');

      final salvo = await _caminhoSalvo();
      expect(salvo, isNotNull);
      expect(File(salvo!).parent.path, documentos.path);
      expect(_caminhoNoAvatar(tester), salvo);
    });

    testWidgets('ao reabrir o app a foto salva volta no avatar', (
      tester,
    ) async {
      final salva = File('${documentos.path}${Platform.pathSeparator}foto.png')
        ..writeAsBytesSync(_png);
      SharedPreferences.setMockInitialValues({
        FotoPerfilStorage.chaveCaminho: salva.path,
      });

      await _abrirApp(tester);

      expect(_caminhoNoAvatar(tester), salva.path);
      expect(find.byIcon(Icons.person), findsNothing);
    });

    testWidgets(
      'se o arquivo sumiu, abre com o avatar padrão e limpa a chave',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          FotoPerfilStorage.chaveCaminho:
              '${documentos.path}${Platform.pathSeparator}apagada.png',
        });

        await _abrirApp(tester);

        expect(_avatar(tester).backgroundImage, isNull);
        expect(await _caminhoSalvo(), isNull);
      },
    );

    testWidgets('Remover Foto também apaga a chave e o arquivo', (
      tester,
    ) async {
      picker.resultado = XFile(_fotoNoCache('galeria.png').path);
      await _abrirApp(tester);
      await _escolherOpcao(tester, 'Escolher da Galeria');
      expect(_arquivosEmDocumentos(), hasLength(1));
      // Espera o avatar terminar de ler o arquivo: no Windows não dá para
      // apagar um arquivo que ainda está aberto para leitura
      await _aguardarImagemCarregada(tester, _avatar(tester).backgroundImage!);

      await _escolherOpcao(tester, 'Remover Foto');

      expect(await _caminhoSalvo(), isNull);
      expect(_arquivosEmDocumentos(), isEmpty);
      expect(
        find.text('Não foi possível carregar a imagem. Tente novamente.'),
        findsNothing,
      );
    });
  });

  group('Correções', () {
    testWidgets('permissão da câmera negada vira aviso em português', (
      tester,
    ) async {
      picker.erro = PlatformException(
        code: 'camera_access_denied',
        message: 'The user did not allow camera access.',
      );
      await _abrirApp(tester);

      await _escolherOpcao(tester, 'Tirar Foto com a Câmera');

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Acesso à câmera negado. Libere a permissão nas configurações do '
          'aparelho.',
        ),
        findsOneWidget,
      );
      expect(_avatar(tester).backgroundImage, isNull);
    });

    testWidgets('sem suporte à câmera (Windows) o menu mostra só a galeria', (
      tester,
    ) async {
      picker.suportaCamera = false;
      await _abrirApp(tester);

      await _abrirMenu(tester);

      expect(find.text('Tirar Foto com a Câmera'), findsNothing);
      expect(find.text('Escolher da Galeria'), findsOneWidget);
    });

    testWidgets('foto perdida pelo Android é recuperada ao reabrir o app', (
      tester,
    ) async {
      final perdida = _fotoNoCache('perdida.png');
      picker.fotoPerdida = LostDataResponse(
        file: XFile(perdida.path),
        type: RetrieveType.image,
      );

      await _abrirApp(tester);

      final salvo = await _caminhoSalvo();
      expect(salvo, isNotNull);
      expect(File(salvo!).parent.path, documentos.path);
      expect(_caminhoNoAvatar(tester), salvo);
    });

    testWidgets(
      'fechar a tela com a câmera aberta não chama setState depois do dispose',
      (tester) async {
        picker.pendente = Completer<XFile?>();
        await _abrirApp(tester);
        await _abrirMenu(tester);
        await tester.tap(find.text('Tirar Foto com a Câmera'));
        await tester.pump();

        await tester.pumpWidget(const SizedBox());
        picker.pendente!.complete(XFile(_fotoNoCache('tarde.png').path));
        await _aguardarDisco(tester);

        expect(tester.takeException(), isNull);
      },
    );
  });
}
