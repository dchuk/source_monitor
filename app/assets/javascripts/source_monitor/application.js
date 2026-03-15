import { Application } from "@hotwired/stimulus";
import AsyncSubmitController from "./controllers/async_submit_controller";
import NotificationController from "./controllers/notification_controller";
import NotificationContainerController from "./controllers/notification_container_controller";
import DropdownController from "./controllers/dropdown_controller";
import ModalController from "./controllers/modal_controller";
import ConfirmNavigationController from "./controllers/confirm_navigation_controller";
import SelectAllController from "./controllers/select_all_controller";
import FilterSubmitController from "./controllers/filter_submit_controller";
import "./turbo_actions";

const application = Application.start();

application.register("notification", NotificationController);
application.register("notification-container", NotificationContainerController);
application.register("async-submit", AsyncSubmitController);
application.register("dropdown", DropdownController);
application.register("modal", ModalController);
application.register("confirm-navigation", ConfirmNavigationController);
application.register("select-all", SelectAllController);
application.register("filter-submit", FilterSubmitController);

export default application;
