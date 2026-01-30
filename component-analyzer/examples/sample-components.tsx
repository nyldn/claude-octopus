/**
 * Sample React Components for Testing
 * Demonstrates various component patterns and prop definitions
 */

import React, { forwardRef, memo } from 'react';
import PropTypes from 'prop-types';

// ============================================================================
// Function Component with TypeScript Interface
// ============================================================================

interface ButtonProps {
  /**
   * Button variant style
   */
  variant: 'primary' | 'secondary' | 'danger';

  /**
   * Button size
   */
  size?: 'small' | 'medium' | 'large';

  /**
   * Disabled state
   */
  disabled?: boolean;

  /**
   * Button content
   */
  children: React.ReactNode;

  /**
   * Click handler
   */
  onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void;
}

export function Button({ variant, size = 'medium', disabled, children, onClick }: ButtonProps) {
  return (
    <button
      className={`btn btn-${variant} btn-${size}`}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  );
}

// ============================================================================
// Arrow Function Component with Type Alias
// ============================================================================

type CardProps = {
  title: string;
  description?: string;
  footer?: React.ReactNode;
  variant?: 'elevated' | 'outlined' | 'filled';
};

export const Card: React.FC<CardProps> = ({ title, description, footer, variant = 'elevated' }) => {
  return (
    <div className={`card card-${variant}`}>
      <div className="card-header">
        <h3>{title}</h3>
      </div>
      {description && (
        <div className="card-body">
          <p>{description}</p>
        </div>
      )}
      {footer && <div className="card-footer">{footer}</div>}
    </div>
  );
};

// ============================================================================
// Class Component with Generic Props
// ============================================================================

interface ListProps<T> {
  items: T[];
  renderItem: (item: T, index: number) => React.ReactNode;
  keyExtractor: (item: T) => string | number;
}

export class List<T> extends React.Component<ListProps<T>> {
  render() {
    const { items, renderItem, keyExtractor } = this.props;

    return (
      <ul className="list">
        {items.map((item, index) => (
          <li key={keyExtractor(item)}>
            {renderItem(item, index)}
          </li>
        ))}
      </ul>
    );
  }
}

// ============================================================================
// Component with PropTypes
// ============================================================================

export function Alert({ type, message, onClose }) {
  return (
    <div className={`alert alert-${type}`}>
      <span>{message}</span>
      {onClose && <button onClick={onClose}>×</button>}
    </div>
  );
}

Alert.propTypes = {
  type: PropTypes.oneOf(['info', 'warning', 'error', 'success']).isRequired,
  message: PropTypes.string.isRequired,
  onClose: PropTypes.func
};

Alert.defaultProps = {
  type: 'info'
};

// ============================================================================
// ForwardRef Component
// ============================================================================

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ label, error, ...props }, ref) => {
    return (
      <div className="input-group">
        {label && <label>{label}</label>}
        <input ref={ref} {...props} />
        {error && <span className="error">{error}</span>}
      </div>
    );
  }
);

Input.displayName = 'Input';

// ============================================================================
// Memo Component
// ============================================================================

interface AvatarProps {
  src: string;
  alt: string;
  size?: number;
  rounded?: boolean;
}

export const Avatar = memo<AvatarProps>(({ src, alt, size = 40, rounded = true }) => {
  return (
    <img
      src={src}
      alt={alt}
      width={size}
      height={size}
      className={rounded ? 'avatar-rounded' : 'avatar'}
    />
  );
});

Avatar.displayName = 'Avatar';

// ============================================================================
// Higher-Order Component
// ============================================================================

interface WithLoadingProps {
  isLoading: boolean;
}

export function withLoading<P extends object>(
  Component: React.ComponentType<P>
): React.FC<P & WithLoadingProps> {
  return ({ isLoading, ...props }) => {
    if (isLoading) {
      return <div className="loading">Loading...</div>;
    }

    return <Component {...(props as P)} />;
  };
}

// ============================================================================
// Render Props Component
// ============================================================================

interface ToggleProps {
  defaultValue?: boolean;
  children: (state: { on: boolean; toggle: () => void }) => React.ReactNode;
}

export function Toggle({ defaultValue = false, children }: ToggleProps) {
  const [on, setOn] = React.useState(defaultValue);

  const toggle = () => setOn(prev => !prev);

  return <>{children({ on, toggle })}</>;
}

// ============================================================================
// Polymorphic Component
// ============================================================================

type PolymorphicProps<C extends React.ElementType> = {
  as?: C;
  variant?: 'primary' | 'secondary';
  children: React.ReactNode;
} & React.ComponentPropsWithoutRef<C>;

export function Box<C extends React.ElementType = 'div'>({
  as,
  variant = 'primary',
  children,
  ...props
}: PolymorphicProps<C>) {
  const Component = as || 'div';

  return (
    <Component className={`box box-${variant}`} {...props}>
      {children}
    </Component>
  );
}

// ============================================================================
// Discriminated Union Props
// ============================================================================

type IconButtonProps =
  | {
      variant: 'icon';
      icon: React.ReactNode;
      label: string;
      children?: never;
    }
  | {
      variant: 'text';
      icon?: never;
      label?: never;
      children: React.ReactNode;
    };

export function IconButton(props: IconButtonProps) {
  if (props.variant === 'icon') {
    return (
      <button className="icon-button" aria-label={props.label}>
        {props.icon}
      </button>
    );
  }

  return <button className="text-button">{props.children}</button>;
}

// ============================================================================
// Compound Component Pattern
// ============================================================================

interface TabsProps {
  children: React.ReactNode;
  defaultActiveKey?: string;
}

interface TabProps {
  eventKey: string;
  title: string;
  children: React.ReactNode;
}

function TabsContainer({ children, defaultActiveKey }: TabsProps) {
  const [activeKey, setActiveKey] = React.useState(defaultActiveKey);

  return (
    <div className="tabs">
      {React.Children.map(children, (child) => {
        if (React.isValidElement<TabProps>(child)) {
          return React.cloneElement(child, {
            ...child.props,
            active: child.props.eventKey === activeKey
          } as any);
        }
        return child;
      })}
    </div>
  );
}

function Tab({ title, children, eventKey, ...props }: TabProps & { active?: boolean }) {
  return (
    <div className="tab" data-key={eventKey} {...props}>
      <div className="tab-title">{title}</div>
      <div className="tab-content">{children}</div>
    </div>
  );
}

export const Tabs = Object.assign(TabsContainer, { Tab });

// ============================================================================
// Component with Default Props (Legacy Pattern)
// ============================================================================

interface BadgeProps {
  color: string;
  count: number;
  showZero: boolean;
  children: React.ReactNode;
}

export function Badge({ color, count, showZero, children }: Partial<BadgeProps>) {
  if (count === 0 && !showZero) return <>{children}</>;

  return (
    <div className="badge-container">
      {children}
      <span className={`badge badge-${color}`}>{count}</span>
    </div>
  );
}

Badge.defaultProps = {
  color: 'red',
  count: 0,
  showZero: false
};
