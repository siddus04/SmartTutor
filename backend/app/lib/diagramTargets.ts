export const DIAGRAM_TARGET_CLASSES = [
  "vertices",
  "segments",
  "angles",
  "enclosed_regions",
  "symbolic_marks"
] as const;

export type DiagramTargetClass = typeof DIAGRAM_TARGET_CLASSES[number];

export const DIAGRAM_TARGET_CLASS_SET = new Set<string>(DIAGRAM_TARGET_CLASSES);

export function normalizeDiagramTargetClass(value: string | null | undefined): DiagramTargetClass | null {
  if (!value) return null;
  const normalized = value.trim().toLowerCase().replace(/\s+/g, "_");
  if (normalized === "vertex" || normalized === "point" || normalized === "points") return "vertices";
  if (normalized === "segment" || normalized === "side") return "segments";
  if (normalized === "angle") return "angles";
  if (normalized === "region" || normalized === "regions" || normalized === "enclosed_region") return "enclosed_regions";
  if (normalized === "symbolic" || normalized === "symbol" || normalized === "mark") return "symbolic_marks";
  return DIAGRAM_TARGET_CLASS_SET.has(normalized) ? (normalized as DiagramTargetClass) : null;
}
