// Hanko's own icon set under the names the app's components use — a drop-in
// for lucide-react (removed: it made the app look like every other generated
// UI). Same call shape: <Swords size={16} className="…" />, and components can
// still be passed around as values (icon={Swords}).

import type { SVGProps } from "react";
import Icon, { type IconName } from "./Icon";

export type IconComponent = (props: { size?: number; className?: string } & Omit<SVGProps<SVGSVGElement>, "name">) => React.JSX.Element;
/** Name kept from lucide-react so components typed with it still work. */
export type LucideIcon = IconComponent;

function make(name: IconName, display: string): IconComponent {
  const C: IconComponent = (props) => <Icon name={name} {...props} />;
  (C as { displayName?: string }).displayName = display;
  return C;
}

export const AlertCircle = make("alert", "AlertCircle");
export const ArrowLeft = make("back", "ArrowLeft");
export const ArrowRight = make("forward", "ArrowRight");
export const Bot = make("bot", "Bot");
export const Check = make("check", "Check");
export const ChevronDown = make("chevronDown", "ChevronDown");
export const ChevronRight = make("chevron", "ChevronRight");
export const Copy = make("copy", "Copy");
export const Download = make("download", "Download");
export const Dumbbell = make("dumbbell", "Dumbbell");
export const Eye = make("eye", "Eye");
export const Flame = make("flame", "Flame");
export const FolderClosed = make("folder", "FolderClosed");
export const FolderOpen = make("folder", "FolderOpen");
export const FolderPlus = make("folder", "FolderPlus");
export const Globe = make("globe", "Globe");
export const GraduationCap = make("cards", "GraduationCap");
export const Grid3x3 = make("grid", "Grid3x3");
export const Image = make("image", "Image");
export const Languages = make("languages", "Languages");
export const Layers = make("library", "Layers");
export const LayoutDashboard = make("today", "LayoutDashboard");
export const LayoutGrid = make("grid", "LayoutGrid");
export const LayoutList = make("list", "LayoutList");
export const Link2 = make("link", "Link2");
export const List = make("list", "List");
export const Loader2 = make("spinner", "Loader2");
export const Lock = make("lock", "Lock");
export const LogIn = make("signIn", "LogIn");
export const LogOut = make("signOut", "LogOut");
export const MoreHorizontal = make("more", "MoreHorizontal");
export const Pause = make("pause", "Pause");
export const PenLine = make("write", "PenLine");
export const Pencil = make("edit", "Pencil");
export const Play = make("play", "Play");
export const Plus = make("plus", "Plus");
export const RefreshCw = make("refresh", "RefreshCw");
export const RotateCcw = make("retry", "RotateCcw");
export const Search = make("search", "Search");
export const Settings2 = make("adjust", "Settings2");
export const Share2 = make("share", "Share2");
export const Shuffle = make("shuffle", "Shuffle");
export const Skull = make("skull", "Skull");
export const Snowflake = make("snowflake", "Snowflake");
export const Sparkle = make("sparkle", "Sparkle");
export const Swords = make("practice", "Swords");
export const Trash2 = make("trash", "Trash2");
export const Trophy = make("trophy", "Trophy");
export const Undo2 = make("undo", "Undo2");
export const Users = make("friends", "Users");
export const Versus = make("duel", "Versus");
export const Volume2 = make("sound", "Volume2");
export const X = make("close", "X");
