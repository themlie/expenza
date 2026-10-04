"""Servislerin fırlattığı istisnalar; main.py bunları {"detail": ...} cevabına çevirir."""


class ServiceError(Exception):
    status_code = 400

    def __init__(self, detail: str):
        super().__init__(detail)
        self.detail = detail


class NotFound(ServiceError):
    status_code = 404


class RuleViolation(ServiceError):
    """İstek geçerli biçimde ama bir iş kuralını çiğniyor (ör. birikimden fazla çekim)."""

    status_code = 400
