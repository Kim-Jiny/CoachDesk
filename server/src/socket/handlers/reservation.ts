import { Socket } from 'socket.io';

// Reservation events are currently emitted from REST routes.
// This handler is an extension point for future socket-initiated reservation actions.
export function registerReservationHandlers(socket: Socket) {
  // Future: socket-based reservation actions can be added here
}
