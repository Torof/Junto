import type { LucideIcon } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';

type IconProps = {
  icon: LucideIcon;
  size?: number;
  color?: string;
  strokeWidth?: number;
};

export function Icon({ icon: LucideIconComponent, size = 22, color, strokeWidth = 2 }: IconProps) {
  const colors = useColors();
  return <LucideIconComponent size={size} color={color ?? colors.textPrimary} strokeWidth={strokeWidth} />;
}
