import 'dart:js_interop';

Stream<List<int>> openRead(String path) {
  return Stream.multi((listener) {
    ReadStream stream;
    try {
      stream = fs.createReadStream(path.toJS);
    } on Object catch (e, s) {
      listener
        ..addError(e, s)
        // ignore: discarded_futures
        ..close();
      return;
    }

    stream.on(
      'error'.toJS,
      (JSObject error) {
        listener.addErrorSync(error);
      }.toJS,
    );
    stream.on(
      'data'.toJS,
      (JSAny event) {
        final buffer = event as Buffer;
        final toDart = buffer.buffer.toDart
            .asUint8List(buffer.byteOffset.toDartInt, buffer.length.toDartInt);
        listener.addSync(toDart);
      }.toJS,
    );
    stream.on('end'.toJS, (() => listener.closeSync()).toJS);

    listener
      ..onPause = () {
        stream.pause();
      }
      ..onResume = () {
        stream.resume();
      }
      ..onCancel = () {
        stream.destroy();
      };
  });
}

@JS()
external JSObject require(JSString module);

FileSystemModule get fs => require('fs'.toJS) as FileSystemModule;

extension type FileSystemModule._(JSObject _) implements JSObject {
  external ReadStream createReadStream(JSString path);
}

extension type ReadStream._(JSObject _) implements JSObject {
  external void destroy();
  external void pause();
  external void resume();

  external void on(JSString eventName, JSFunction listener);
  external void removeAllListeners(JSString eventName);
}

extension type Buffer._(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
  external JSNumber get byteOffset;
  external JSNumber get length;
}
