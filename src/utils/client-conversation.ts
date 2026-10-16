import type { Conversation } from '@/services/conversation-service';

// A pro ↔ client thread: a DM opened (or retagged) by a confirmed booking
// (initiated_from = 'booking', 00418/00451). Shared by the messagerie chip,
// the Espace pro tile, the menu badge and the filtered client list.
export const isClientConversation = (c: Conversation): boolean =>
  c.type === 'dm' && c.initiated_from === 'booking';
