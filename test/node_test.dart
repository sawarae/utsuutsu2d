import 'package:flutter_test/flutter_test.dart';
import 'package:utsutsu2d/utsutsu2d.dart';

void main() {
  group('PuppetNode', () {
    test('basic creation', () {
      final node = PuppetNode(uuid: 1, name: 'test');

      expect(node.uuid, 1);
      expect(node.name, 'test');
      expect(node.enabled, true);
      expect(node.zsort, 0);
    });
  });

  group('PuppetNodeTree', () {
    test('create with root', () {
      final root = PuppetNode(uuid: 0, name: 'root');
      final tree = PuppetNodeTree.withRoot(root);

      expect(tree.nodeCount, 1);
      expect(tree.root.data.name, 'root');
    });

    test('add children', () {
      final root = PuppetNode(uuid: 0, name: 'root');
      final tree = PuppetNodeTree.withRoot(root);

      final child1 = PuppetNode(uuid: 1, name: 'child1');
      final child2 = PuppetNode(uuid: 2, name: 'child2');

      tree.addNode(child1, 0);
      tree.addNode(child2, 0);

      expect(tree.nodeCount, 3);
      expect(tree.getChildren(0).length, 2);
    });

    test('pre-order traversal', () {
      final root = PuppetNode(uuid: 0, name: 'root');
      final tree = PuppetNodeTree.withRoot(root);

      tree.addNode(PuppetNode(uuid: 1, name: 'child1'), 0);
      tree.addNode(PuppetNode(uuid: 2, name: 'child2'), 0);
      tree.addNode(PuppetNode(uuid: 3, name: 'grandchild'), 1);

      final names = tree.preOrder().map((n) => n.data.name).toList();

      expect(names[0], 'root');
      expect(names.contains('child1'), true);
      expect(names.contains('child2'), true);
      expect(names.contains('grandchild'), true);
    });

    test('duplicate UUID throws', () {
      final root = PuppetNode(uuid: 0, name: 'root');
      final tree = PuppetNodeTree.withRoot(root);

      tree.addNode(PuppetNode(uuid: 1, name: 'child'), 0);

      expect(
        () => tree.addNode(PuppetNode(uuid: 1, name: 'duplicate'), 0),
        throwsArgumentError,
      );
    });
  });
}
