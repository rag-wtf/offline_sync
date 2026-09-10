import 'dart:io';

/// Native (IO) implementation of network reachability check.
Future<bool> checkNetworkReachability() async {
  try {
    final interfaces = await NetworkInterface.list();
    final hasInterface = interfaces.any(
      (i) => !i.name.startsWith('lo') && i.addresses.any((a) => !a.isLoopback),
    );
    if (!hasInterface) return false;
    final lookup = await InternetAddress.lookup(
      'huggingface.co',
    ).timeout(const Duration(seconds: 3));
    return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
  } on Object {
    return false;
  }
}
