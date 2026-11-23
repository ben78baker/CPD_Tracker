import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'handoff permits shared preferences and evidence only after approval',
    () async {
      final gate = LegacyWriteGate();
      expect(await gate.write(() async => 'legacy'), 'legacy');
      await gate.freeze(() async {
        await expectLater(gate.writeShared(() async {}), throwsStateError);
        gate.seal(allowSharedWrites: true);
      });
      await gate.writeShared(() async {
        expect(await gate.writeShared(() async => 'shared'), 'shared');
        await expectLater(gate.write(() async {}), throwsStateError);
      });
      final recovery = LegacyWriteGate();
      await recovery.freeze(() async => recovery.seal());
      await expectLater(recovery.writeShared(() async {}), throwsStateError);
    },
  );
}
