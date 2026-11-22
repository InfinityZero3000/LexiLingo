import type { LucideIcon } from "lucide-react";
import {
  BadgeCheck, Banknote, BookOpen, BriefcaseBusiness, Building2, Car, Coffee, Gamepad2,
  GraduationCap, Handshake, HeartPulse, Home, Landmark, Leaf, MapPinned, MessageSquare, Mic,
  Plane, PlugZap, School, Settings2, ShoppingCart, Siren, Sparkles, Stethoscope, Sun, Users,
  Utensils, Wifi, Wrench,
} from "lucide-react";
import type { ICON_KEYS } from "../../lib/topicForm";

type IconKey = (typeof ICON_KEYS)[number];

/** One entry per key the app can draw (ICON_KEYS), so the picker never offers an icon the app lacks. */
export const TOPIC_ICONS: { key: IconKey; label: string; icon: LucideIcon }[] = [
  { key: "travel", label: "Travel", icon: Plane },
  { key: "hotel", label: "Hotel", icon: Building2 },
  { key: "directions", label: "Directions", icon: MapPinned },
  { key: "transport", label: "Transport", icon: Car },
  { key: "work", label: "Work", icon: BriefcaseBusiness },
  { key: "business", label: "Business", icon: Handshake },
  { key: "finance", label: "Finance", icon: Banknote },
  { key: "shopping", label: "Shopping", icon: ShoppingCart },
  { key: "food", label: "Food", icon: Utensils },
  { key: "cafe", label: "Cafe", icon: Coffee },
  { key: "health", label: "Health", icon: HeartPulse },
  { key: "doctor", label: "Doctor", icon: Stethoscope },
  { key: "emergency", label: "Emergency", icon: Siren },
  { key: "education", label: "Education", icon: GraduationCap },
  { key: "library", label: "Library", icon: BookOpen },
  { key: "classroom", label: "Classroom", icon: School },
  { key: "technology", label: "Technology", icon: PlugZap },
  { key: "internet", label: "Internet", icon: Wifi },
  { key: "ai", label: "AI", icon: Sparkles },
  { key: "services", label: "Services", icon: Settings2 },
  { key: "repair", label: "Repair", icon: Wrench },
  { key: "housing", label: "Housing", icon: Home },
  { key: "daily_life", label: "Daily life", icon: Sun },
  { key: "culture", label: "Culture", icon: Landmark },
  { key: "leisure", label: "Leisure", icon: Gamepad2 },
  { key: "social", label: "Social", icon: Users },
  { key: "media", label: "Media", icon: Mic },
  { key: "environment", label: "Environment", icon: Leaf },
  { key: "achievement", label: "Achievement", icon: BadgeCheck },
  { key: "chat", label: "Chat", icon: MessageSquare },
];

export const iconFor = (key?: string | null, category?: string | null): LucideIcon => {
  const norm = (v?: string | null) => (v || "").toLowerCase().trim().replace(/ /g, "_");
  return (
    TOPIC_ICONS.find((item) => item.key === norm(key))?.icon ??
    TOPIC_ICONS.find((item) => item.key === norm(category))?.icon ??
    MessageSquare
  );
};

export const iconLabel = (key: string) => TOPIC_ICONS.find((item) => item.key === key)?.label ?? key;
