import '../../../../../core/services/ai_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../domain/repositories/chat_repository.dart';

/// Manages multiple AI services and provides fallback logic
/// Uses Strategy Pattern to switch between different AI models
class AIServiceManager {
  final List<AIService> _services;
  AIService? _currentService;

  AIServiceManager({
    required List<AIService> services,
    AIService? defaultService,
  }) : _services = services {
    // Set default service or use first available
    if (defaultService != null && _services.contains(defaultService)) {
      _currentService = defaultService;
    } else if (_services.isNotEmpty) {
      _currentService = _services.first;
    }
  }

  /// Get the currently active AI service
  AIService? get currentService => _currentService;

  /// Get all available services
  List<AIService> get allServices => List.unmodifiable(_services);

  /// Get service by model type
  AIService? getServiceByModel(AIModel model) {
    try {
      return _services.firstWhere((service) => service.modelType == model);
    } catch (e) {
      return null;
    }
  }

  /// Switch to a specific AI model
  /// Returns true if successful, false if model not available
  bool switchModel(AIModel model) {
    final service = getServiceByModel(model);
    if (service != null && service.isConfigured()) {
      _currentService = service;
      return true;
    }
    return false;
  }

  /// Generate AI response with automatic fallback
  /// Tries current service first, then falls back to other services
  Future<String> getResponse({
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
    double temperature = 0.7,
    AIModel? preferredModel,
  }) async {
    // Try preferred model first if specified
    if (preferredModel != null) {
      final preferredService = getServiceByModel(preferredModel);
      if (preferredService != null && preferredService.isConfigured()) {
        try {
          return await preferredService.generateResponse(
            prompt: prompt,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            temperature: temperature,
          );
        } catch (e) {
          // Log error but continue to fallback
          print('Preferred model $preferredModel failed: $e');
        }
      }
    }

    // Try current service
    if (_currentService != null && _currentService!.isConfigured()) {
      try {
        return await _currentService!.generateResponse(
          prompt: prompt,
          systemPrompt: systemPrompt,
          conversationHistory: conversationHistory,
          temperature: temperature,
        );
      } catch (e) {
        print('Current service ${_currentService!.modelName} failed: $e');
      }
    }

    // Fallback to other services
    for (final service in _services) {
      if (service == _currentService) continue;
      if (!service.isConfigured()) continue;

      try {
        final response = await service.generateResponse(
          prompt: prompt,
          systemPrompt: systemPrompt,
          conversationHistory: conversationHistory,
          temperature: temperature,
        );
        
        // Switch to this working service
        _currentService = service;
        return response;
      } catch (e) {
        print('Fallback service ${service.modelName} failed: $e');
        continue;
      }
    }

    // All services failed
    throw AIServiceException(
      'All AI services failed to generate a response',
      details: 'Tried ${_services.length} services',
    );
  }

  /// Test all services and return their availability status
  Future<Map<AIModel, bool>> testAllServices() async {
    final results = <AIModel, bool>{};
    
    for (final service in _services) {
      if (!service.isConfigured()) {
        results[service.modelType] = false;
        continue;
      }
      
      try {
        final isAvailable = await service.testConnection();
        results[service.modelType] = isAvailable;
      } catch (e) {
        results[service.modelType] = false;
      }
    }
    
    return results;
  }

  /// Get list of configured services
  List<AIService> getConfiguredServices() {
    return _services.where((s) => s.isConfigured()).toList();
  }

  /// Check if any service is configured
  bool hasConfiguredService() {
    return _services.any((s) => s.isConfigured());
  }
}
