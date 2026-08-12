import { NotificationsView } from '@/components/notifications-view';

// Notifications now live inside the messaging hub's "Notifications" tab
// (navbar refonte 2026-08-12). This route is kept (off the tab bar) so any
// direct navigation still resolves.
export default function NotificationsScreen() {
  return <NotificationsView />;
}
