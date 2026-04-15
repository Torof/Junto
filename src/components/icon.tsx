import type { LucideIcon } from 'lucide-react-native';
import { colors } from '@/constants/theme';

type IconProps = {
  icon: LucideIcon;
  size?: number;
  color?: string;
  strokeWidth?: number;
};

export function Icon({ icon: LucideIconComponent, size = 22, color = colors.textPrimary, strokeWidth = 2 }: IconProps) {
  return <LucideIconComponent size={size} color={color} strokeWidth={strokeWidth} />;
}
