/// Components module for utsutsu2d
library;

export 'drawable.dart';
export 'mesh.dart';
export 'composite.dart';
export 'mesh_group.dart';
export 'simple_physics.dart';
export 'path_deform.dart';

import 'drawable.dart';
import 'mesh.dart';
import 'composite.dart';
import 'mesh_group.dart';
import 'simple_physics.dart';
import 'path_deform.dart';
import '../math/deform.dart';

/// Container for all node components
class NodeComponents {
  Drawable? drawable;
  Mesh? mesh;
  TexturedMesh? texturedMesh;
  Composite? composite;
  MeshGroup? meshGroup;
  SimplePhysics? simplePhysics;
  DeformStack? deformStack;
  PathDeform? pathDeform;

  NodeComponents({
    this.drawable,
    this.mesh,
    this.texturedMesh,
    this.composite,
    this.meshGroup,
    this.simplePhysics,
    this.deformStack,
    this.pathDeform,
  });

  /// Check if this node is drawable
  bool get isDrawable =>
      drawable != null && mesh != null && texturedMesh != null;

  /// Check if this node is a composite
  bool get isComposite => composite != null;

  /// Check if this node is a mesh group
  bool get isMeshGroup => meshGroup != null;

  /// Check if this node has physics
  bool get hasPhysics => simplePhysics != null;

  /// Check if this node is a path deformer
  bool get isPathDeform => pathDeform != null;
}
