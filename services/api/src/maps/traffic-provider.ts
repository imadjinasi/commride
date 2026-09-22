import type {
  TrafficIncident,
  TrafficIncidentInput,
} from './models';

export interface TrafficIncidentProvider {
  incidentsAlongRoute(
    input: TrafficIncidentInput,
  ): Promise<readonly TrafficIncident[]>;
}
