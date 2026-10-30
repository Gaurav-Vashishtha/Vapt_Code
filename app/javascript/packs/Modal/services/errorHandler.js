/**
 * Error Handler for GraphQL Operations
 * Provides centralized error handling and user-friendly error messages
 */

export class GraphQLErrorHandler {
  constructor() {
    this.errorCallbacks = new Map();
    this.setupDefaultErrorHandlers();
  }

  /**
   * Setup default error handlers for common scenarios
   */
  setupDefaultErrorHandlers() {
    // Authentication errors
    this.registerErrorHandler('AUTH_ERROR', (error) => {
      console.error('Authentication error:', error);
      return {
        userMessage: 'Authentication failed. Please refresh the page and try again.',
        shouldRetry: false,
        action: 'REFRESH_PAGE'
      };
    });

    // Network errors
    this.registerErrorHandler('NETWORK_ERROR', (error) => {
      console.error('Network error:', error);
      return {
        userMessage: 'Network connection issue. Please check your internet connection and try again.',
        shouldRetry: true,
        action: 'RETRY'
      };
    });

    // Rate limiting
    this.registerErrorHandler('RATE_LIMIT', (error) => {
      console.error('Rate limit exceeded:', error);
      return {
        userMessage: 'Too many requests. Please wait a moment and try again.',
        shouldRetry: true,
        action: 'WAIT_AND_RETRY'
      };
    });

    // Cart errors
    this.registerErrorHandler('CART_ERROR', (error) => {
      console.error('Cart operation error:', error);
      return {
        userMessage: 'Cart operation failed. Please try again or refresh the page.',
        shouldRetry: true,
        action: 'RETRY'
      };
    });

    // Customer errors
    this.registerErrorHandler('CUSTOMER_ERROR', (error) => {
      console.error('Customer operation error:', error);
      return {
        userMessage: 'Customer operation failed. Please check your information and try again.',
        shouldRetry: false,
        action: 'SHOW_ERROR'
      };
    });

    // Generic GraphQL errors
    this.registerErrorHandler('GRAPHQL_ERROR', (error) => {
      console.error('GraphQL error:', error);
      return {
        userMessage: 'An unexpected error occurred. Please try again.',
        shouldRetry: true,
        action: 'RETRY'
      };
    });
  }

  /**
   * Register a custom error handler
   */
  registerErrorHandler(errorType, handler) {
    this.errorCallbacks.set(errorType, handler);
  }

  /**
   * Classify error type based on error details
   */
  classifyError(error) {
    if (error.name === 'TypeError' && error.message.includes('fetch')) {
      return 'NETWORK_ERROR';
    }

    if (error.status === 401 || error.status === 403) {
      return 'AUTH_ERROR';
    }

    if (error.status === 429) {
      return 'RATE_LIMIT';
    }

    if (error.status >= 500) {
      return 'NETWORK_ERROR';
    }

    if (error.name === 'GraphQLError') {
      if (error.errors && error.errors.length > 0) {
        const firstError = error.errors[0];
        
        if (firstError.message.includes('cart')) {
          return 'CART_ERROR';
        }
        
        if (firstError.message.includes('customer')) {
          return 'CUSTOMER_ERROR';
        }
        
        if (firstError.message.includes('Storefront access token')) {
          return 'AUTH_ERROR';
        }
      }
      return 'GRAPHQL_ERROR';
    }

    return 'GRAPHQL_ERROR';
  }

  /**
   * Handle error and return appropriate response
   */
  handleError(error, context = {}) {
    const errorType = this.classifyError(error);
    const handler = this.errorCallbacks.get(errorType);
    
    if (handler) {
      return handler(error, context);
    }

    // Default error handling
    return {
      userMessage: 'An unexpected error occurred. Please try again.',
      shouldRetry: false,
      action: 'SHOW_ERROR'
    };
  }

  /**
   * Execute operation with error handling wrapper
   */
  async executeWithErrorHandling(operation, context = {}) {
    try {
      return await operation();
    } catch (error) {
      const errorResponse = this.handleError(error, context);
      
      // Log error for debugging
      console.error('Operation failed:', {
        error,
        context,
        errorResponse
      });

      // Throw enhanced error with user-friendly message
      const enhancedError = new Error(errorResponse.userMessage);
      enhancedError.originalError = error;
      enhancedError.shouldRetry = errorResponse.shouldRetry;
      enhancedError.action = errorResponse.action;
      enhancedError.context = context;
      
      throw enhancedError;
    }
  }

  /**
   * Retry operation with exponential backoff
   */
  async retryOperation(operation, maxRetries = 3, baseDelay = 1000) {
    let lastError;
    
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        
        if (!error.shouldRetry || attempt === maxRetries) {
          throw error;
        }
        
        // Wait before retrying
        const delay = baseDelay * Math.pow(2, attempt);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
    
    throw lastError;
  }
}

// Create singleton instance
export const errorHandler = new GraphQLErrorHandler();

// Export utility functions
export const handleGraphQLError = (error, context = {}) => {
  return errorHandler.handleError(error, context);
};

export const executeWithErrorHandling = (operation, context = {}) => {
  return errorHandler.executeWithErrorHandling(operation, context);
};

export const retryOperation = (operation, maxRetries = 3, baseDelay = 1000) => {
  return errorHandler.retryOperation(operation, maxRetries, baseDelay);
};
