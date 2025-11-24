import { Application } from "@hotwired/stimulus";
import AsyncSubmitController from "./controllers/async_submit_controller";
import NotificationController from "./controllers/notification_controller";
import DropdownController from "./controllers/dropdown_controller";
import ModalController from "./controllers/modal_controller";
import ConfirmNavigationController from "./controllers/confirm_navigation_controller";
import "./turbo_actions";

const existingApplication = window.SourceMonitorStimulus;
const application = existingApplication || Application.start();

if (!existingApplication) {
  window.SourceMonitorStimulus = application;
}

application.register("notification", NotificationController);
application.register("async-submit", AsyncSubmitController);
application.register("dropdown", DropdownController);
application.register("modal", ModalController);
application.register("confirm-navigation", ConfirmNavigationController);

export default application;
